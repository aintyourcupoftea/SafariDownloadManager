"""
SafariDownloadManager - interception addon.

Architecture (see FINDINGS.md for how each constraint was discovered):

* Downloads are decided in the `request` hook, BEFORE Safari's request reaches
  the server, by probing the URL ourselves. Short-circuiting there means no
  upstream body is ever pending, so the 204 we hand Safari is clean and
  instant. Deciding in `responseheaders` instead makes Safari wait for the
  upstream body to drain and it gives up on large files
  (ConnectionTerminated error_code:11 at ~72MB of a 159MB file).

* SAFETY: the probe is a real HTTP request carrying the user's cookies, so it
  is fired ONLY at URLs that already look like downloads (extension match).
  Probing every navigation would double-fire side-effecting GET endpoints -
  unsubscribe links, logout, confirm-email, GET-based deletes.

* Downloads that only reveal themselves via Content-Disposition on an
  extensionless URL are caught by the `responseheaders` fallback instead. That
  path cannot give a perfect 204 for huge files, so it trades UX for capture.

* Behaviour is switched through state/STRATEGY, re-read on every call.
  Restarting mitmdump detaches the macOS NEAppProxyProvider binding and
  silently kills ALL capture, so we never restart to change behaviour.
"""
import json
import os
import re
import time
import urllib.parse
import urllib.request
from mitmproxy import http, ctx

# SDM_HOME holds all mutable state and is created by `sdm setup`. It is passed
# in by the launcher so this file works from any install prefix.
HOME_DIR = os.environ.get("SDM_HOME") or os.path.expanduser(
    "~/Library/Application Support/SafariDownloadManager")
ROOT = HOME_DIR
STRATEGY_FILE = os.path.join(HOME_DIR, "state", "STRATEGY")
STATE_FILE = os.path.join(HOME_DIR, "state", "downloads.json")
RPC_PORT = os.environ.get("SDM_RPC_PORT", "6800")
RPC_URL = f"http://127.0.0.1:{RPC_PORT}/jsonrpc"
RPC_SECRET_FILE = os.path.join(HOME_DIR, "state", "rpc.secret")
DEDUPE_WINDOW = 900          # seconds a (name,size) stays claimed
DEST = os.environ.get("SDM_DOWNLOAD_DIR") or os.path.expanduser("~/Downloads")
STAGING = os.path.join(DEST, ".sdm-incomplete")
LOG_DIR = os.path.join(HOME_DIR, "logs")

MIN_SIZE = 128 * 1024
FALLBACK_MAX_DRAIN = 64 * 1024 * 1024   # above this, don't pull a body we're discarding
PROBE_CACHE_MAX = 500

DOWNLOAD_TYPES = {
    "application/octet-stream", "application/zip", "application/x-zip-compressed",
    "application/x-apple-diskimage", "application/x-iso9660-image",
    "application/x-msdownload", "application/vnd.microsoft.portable-executable",
    "application/gzip", "application/x-gzip", "application/x-tar",
    "application/x-7z-compressed", "application/x-rar-compressed",
    "application/x-bzip2", "application/x-xz", "application/x-debian-package",
    "application/vnd.android.package-archive", "application/java-archive",
}
DOWNLOAD_EXTS = (
    ".dmg", ".pkg", ".zip", ".iso", ".tar", ".gz", ".tgz", ".bz2", ".xz", ".7z",
    ".rar", ".exe", ".msi", ".deb", ".rpm", ".apk", ".jar", ".img", ".bin",
    ".mp4", ".mkv", ".avi", ".mov", ".webm", ".flac", ".mp3", ".wav", ".epub",
    ".pdf", ".appimage", ".whl", ".crx", ".xpi",
)
NEVER_TYPES_PREFIX = ("text/html", "text/css", "text/plain", "application/javascript",
                      "text/javascript", "application/json", "application/xml",
                      "text/xml", "image/", "font/")

_active = {}
_probe_cache = {}
_claimed = {}


def _strategy():
    try:
        with open(STRATEGY_FILE) as f:
            return f.read().strip() or "off"
    except OSError:
        return "off"


def running(*_):
    os.makedirs(STAGING, exist_ok=True)
    os.makedirs(os.path.dirname(STRATEGY_FILE), exist_ok=True)
    if not os.path.exists(STRATEGY_FILE):
        with open(STRATEGY_FILE, "w") as f:
            f.write("off")
    ctx.log.warn(f"[SDM] ready. strategy={_strategy()}")


def _safe(name):
    name = os.path.basename((name or "").replace("\\", "/")).strip()
    name = re.sub(r"[\x00-\x1f/:]+", "_", name)
    return name[:200] or "download"


def _unique(path):
    if not os.path.exists(path):
        return path
    stem, ext = os.path.splitext(path)
    if stem.endswith(".tar"):
        stem, ext = stem[:-4], ".tar" + ext
    i = 1
    while os.path.exists(f"{stem} ({i}){ext}"):
        i += 1
    return f"{stem} ({i}){ext}"


def _name_from(headers, *urls):
    """Content-Disposition wins, then the first URL with a usable basename."""
    cd = headers.get("content-disposition", "") or ""
    m = re.search(r"filename\*\s*=\s*([^']*)'[^']*'([^;]+)", cd, re.I)
    if m:
        try:
            return urllib.parse.unquote(m.group(2).strip(), encoding=m.group(1) or "utf-8")
        except Exception:
            pass
    m = (re.search(r'filename\s*=\s*"([^"]+)"', cd, re.I)
         or re.search(r"filename\s*=\s*([^;]+)", cd, re.I))
    if m:
        return m.group(1).strip()
    for u in urls:
        base = os.path.basename(urllib.parse.urlparse(u or "").path)
        if base:
            return urllib.parse.unquote(base)
    return "download"


def _write_state():
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(list(_active.values())[-50:], f, indent=1)
    except OSError:
        pass


def _looks_downloadable(url):
    """Gate for the probe. Only URLs that already look like files get a real
    HTTP request fired at them, so we never trip a side-effecting GET."""
    path = urllib.parse.urlparse(url).path.lower()
    return path.endswith(DOWNLOAD_EXTS)


def _rpc(method, params):
    """JSON-RPC to the long-lived aria2 daemon."""
    try:
        with open(RPC_SECRET_FILE) as f:
            secret = f.read().strip()
    except OSError:
        ctx.log.warn("[SDM] rpc secret missing")
        return None
    body = json.dumps({"jsonrpc": "2.0", "id": "sdm", "method": method,
                       "params": [f"token:{secret}", *params]}).encode()
    req = urllib.request.Request(RPC_URL, data=body,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            out = json.load(r)
    except Exception as e:
        ctx.log.warn(f"[SDM] rpc {method} failed: {e!r}")
        return None
    if "error" in out:
        ctx.log.warn(f"[SDM] rpc {method} error: {out['error']}")
        return None
    return out.get("result")


def _already_claimed(name, total):
    """Dedupe on (name, size), NOT url.

    Presigned URLs carry a fresh token on every request, so URL-keyed dedupe
    silently fails for exactly the links that matter - that is how one .mkv got
    handed off four times, producing 4x8 connections and a wall of HTTP 429s.

    The claim is released as soon as aria2 says the job is no longer running.
    A pure time window would block a legitimate re-download of a file the user
    just deleted, which is a normal thing to do.
    """
    now = time.time()
    key = (name, total)
    for k, (ts, _g) in list(_claimed.items()):
        if now - ts > DEDUPE_WINDOW:
            del _claimed[k]
    held = _claimed.get(key)
    if held:
        ts, gid = held
        if gid:
            st = _rpc("aria2.tellStatus", [gid, ["status"]])
            # complete / error / removed -> the job is done, let a new one through
            if not st or st.get("status") not in ("active", "waiting", "paused"):
                del _claimed[key]
                return False
        return True
    _claimed[key] = (now, None)
    return False


def _claim_gid(name, total, gid):
    _claimed[(name, total)] = (time.time(), gid)


def _handoff(flow, name, total, url=None):
    """Queue the download on the aria2 daemon. One daemon, one job, real GID."""
    hdrs = []
    for k in ("cookie", "referer", "user-agent", "authorization",
              "accept-language", "origin"):
        v = flow.request.headers.get(k)
        if v:
            hdrs.append(f"{k}: {v}")
    opts = {"out": name, "header": hdrs}
    gid = _rpc("aria2.addUri", [[url or flow.request.pretty_url], opts])
    if gid:
        ctx.log.warn(f"[SDM] queued {name} gid={gid}")
    return gid


def _probe(flow):
    url = flow.request.pretty_url
    now = time.time()
    hit = _probe_cache.get(url)
    if hit and hit[1] > now:
        return hit[0]
    if len(_probe_cache) > PROBE_CACHE_MAX:
        _probe_cache.clear()
    ctx.log.warn(f"[SDM] PROBE-FIRED {url[:100]}")
    req = urllib.request.Request(url, method="GET")
    for k in ("cookie", "referer", "user-agent", "accept-language"):
        v = flow.request.headers.get(k)
        if v:
            req.add_header(k, v)
    req.add_header("Range", "bytes=0-0")
    try:
        with urllib.request.urlopen(req, timeout=6) as r:
            info = ({k.lower(): v for k, v in r.headers.items()}, r.status, r.geturl())
    except Exception as e:
        ctx.log.warn(f"[SDM] probe failed {url[:60]}: {e!r}")
        _probe_cache[url] = (None, now + 30)
        return None
    _probe_cache[url] = (info, now + 60)
    return info


def _classify(headers, url, clen):
    cd = (headers.get("content-disposition", "") or "").lower()
    ctype = (headers.get("content-type", "") or "").split(";")[0].strip().lower()
    path = urllib.parse.urlparse(url).path.lower()

    def plausible_size():
        """A missing Content-Length must not be a free pass.

        Chunked junk has no length either, and `clen == 0 or clen >= MIN_SIZE`
        let all of it through - that is how Google's autocomplete endpoint,
        served as `Content-Disposition: attachment; filename="f.txt"` with no
        length, got "downloaded" 13 times. When the size is unknown we only
        trust the response if the filename ends in a real download extension.
        """
        if clen >= MIN_SIZE:
            return True
        if clen > 0:
            return False
        name = _name_from({"content-disposition": cd}, url).lower()
        return name.endswith(DOWNLOAD_EXTS)

    if any(ctype.startswith(p) for p in NEVER_TYPES_PREFIX) and "attachment" not in cd:
        return False
    if "attachment" in cd:
        return plausible_size()
    if ctype in DOWNLOAD_TYPES or path.endswith(DOWNLOAD_EXTS):
        return plausible_size()
    return False


def _record(name, url, total, gid):
    fid = gid or f"{int(time.time()*1000)}"
    _active[fid] = {"id": fid, "gid": gid, "name": name, "url": (url or "")[:400],
                    "total": total, "started": time.time()}
    _write_state()
    return fid


def request(flow: http.HTTPFlow):
    """Primary path. Probe only download-shaped URLs, then short-circuit."""
    if _strategy() != "probe":
        return
    if flow.request.method not in ("GET", "HEAD"):
        return
    if flow.request.headers.get("sec-fetch-dest", "") != "document":
        return
    if not _looks_downloadable(flow.request.pretty_url):
        return                      # SAFETY: never probe arbitrary navigations

    info = _probe(flow)
    if not info:
        return
    headers, status, final_url = info
    total = 0
    crange = headers.get("content-range", "") or ""
    if "/" in crange:
        try:
            total = int(crange.rsplit("/", 1)[1])
        except ValueError:
            total = 0
    if not total:
        try:
            total = int(headers.get("content-length", "0") or 0)
        except ValueError:
            total = 0

    if not _classify(headers, final_url, total):
        return

    name = _safe(_name_from(headers, final_url, flow.request.pretty_url))
    if _already_claimed(name, total):
        ctx.log.warn(f"[SDM] dup suppressed {name}")
        flow.response = http.Response.make(204, b"", {})
        return
    ctx.log.warn(f"[SDM] PROBE-INTERCEPT {name} ({total or '?'} bytes)")
    gid = _handoff(flow, name, total, url=final_url)
    _claim_gid(name, total, gid)
    _record(name, final_url, total, gid)
    flow.response = http.Response.make(204, b"", {})


def responseheaders(flow: http.HTTPFlow):
    """Fallback for downloads with no download-shaped URL - typically
    Content-Disposition on an extensionless path. Cannot give a perfect 204 on
    very large files, so it prioritises capturing the file."""
    if _strategy() != "probe":
        return
    resp = flow.response
    if resp is None or resp.status_code != 200:
        return
    if flow.request.method != "GET":
        return
    # Only a top-level navigation can start a download the user asked for.
    # Background XHR/fetch (sec-fetch-dest: empty|script|image|...) never can,
    # and letting it through is how Google's autocomplete endpoint - served as
    # `Content-Disposition: attachment; filename="f.txt"` - got "downloaded"
    # 13 times.
    if flow.request.headers.get("sec-fetch-dest", "") != "document":
        return
    if flow.request.headers.get("sec-fetch-mode", "") == "cors":
        return
    if _looks_downloadable(flow.request.pretty_url):
        return                      # the probe path already owns these
    try:
        total = int(resp.headers.get("content-length", "0") or 0)
    except ValueError:
        total = 0
    hdrs = {k.lower(): v for k, v in resp.headers.items()}
    if not _classify(hdrs, flow.request.pretty_url, total):
        return

    name = _safe(_name_from(hdrs, flow.request.pretty_url))
    if _already_claimed(name, total):
        ctx.log.warn(f"[SDM] dup suppressed {name}")
        resp.status_code = 204
        resp.reason = "No Content"
        for h in list(resp.headers.keys()):
            del resp.headers[h]
        resp.stream = lambda chunk: b""
        return
    ctx.log.warn(f"[SDM] FALLBACK-INTERCEPT {name} ({total or '?'} bytes)")
    gid = _handoff(flow, name, total)
    _claim_gid(name, total, gid)
    _record(name, flow.request.pretty_url, total, gid)

    resp.status_code = 204
    resp.reason = "No Content"
    for h in list(resp.headers.keys()):
        del resp.headers[h]
    if total and total > FALLBACK_MAX_DRAIN:
        # Don't pull a body we're throwing away; aria2 already has the job.
        ctx.log.warn(f"[SDM] {name}: {total} bytes too large to drain, killing flow")
        try:
            flow.kill()
        except Exception:
            pass
        return
    resp.stream = lambda chunk: b""
