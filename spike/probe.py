"""
Phase 0 spike probe.

Goals (in order):
  1. Do flows from Safari appear at all in --mode local?
  2. What identifies the client process? Dump every candidate attribute
     on client_conn so we read the match string off the tool, not off a guess.
  3. Is Content-Disposition / octet-stream visible in responseheaders,
     i.e. BEFORE the body streams?
  4. Does replacing the response with 204 stop Safari downloading?

Step 4 is armed only when SDM_ARM_204=1, so steps 1-3 can be observed
without breaking normal browsing.
"""
import os
import json
from mitmproxy import http, ctx

ARM_204 = os.environ.get("SDM_ARM_204") == "1"
LOG = "/Users/aintyourcupoftea/Development/SafariDownloadManager/logs/probe.jsonl"

_seen_procs = {}

DOWNLOAD_TYPES = (
    "application/octet-stream", "application/zip", "application/x-apple-diskimage",
    "application/x-msdownload", "application/vnd.microsoft.portable-executable",
    "application/x-gzip", "application/gzip", "application/x-tar",
    "application/x-7z-compressed", "application/x-rar-compressed",
    "application/pdf",
)
DOWNLOAD_EXTS = (
    ".dmg", ".zip", ".pkg", ".iso", ".tar", ".gz", ".tgz", ".bz2", ".xz", ".7z",
    ".rar", ".exe", ".msi", ".deb", ".rpm", ".mp4", ".mkv", ".avi", ".mov",
    ".mp3", ".flac", ".wav", ".img", ".bin", ".apk", ".jar",
)


def _client_fingerprint(client_conn):
    """Dump everything that might identify the originating process."""
    out = {}
    for attr in dir(client_conn):
        if attr.startswith("_"):
            continue
        try:
            val = getattr(client_conn, attr)
        except Exception:
            continue
        if callable(val):
            continue
        # keep it to things that could plausibly name a process
        if isinstance(val, (str, int, float, bool, type(None), tuple, list)):
            out[attr] = str(val)[:200]
    return out


def _log(rec):
    with open(LOG, "a") as f:
        f.write(json.dumps(rec) + "\n")


def running(*_):
    ctx.log.warn(f"[SDM-PROBE] armed_204={ARM_204}  logging -> {LOG}")


def request(flow: http.HTTPFlow):
    cc = flow.client_conn
    fp = _client_fingerprint(cc)
    # Fingerprint each distinct client connection shape only once, loudly.
    key = json.dumps(sorted(fp.items()))[:400]
    if key not in _seen_procs:
        _seen_procs[key] = True
        ctx.log.warn(f"[SDM-PROBE] NEW CLIENT SHAPE for {flow.request.pretty_host}")
        for k, v in sorted(fp.items()):
            ctx.log.warn(f"[SDM-PROBE]     {k} = {v}")
        _log({"kind": "client_shape", "host": flow.request.pretty_host, "fp": fp})


def responseheaders(flow: http.HTTPFlow):
    """Fires BEFORE the body is streamed. This is where interception must work."""
    resp = flow.response
    if resp is None:
        return

    cd = resp.headers.get("content-disposition", "")
    ctype = (resp.headers.get("content-type", "") or "").split(";")[0].strip().lower()
    clen = resp.headers.get("content-length", "")
    path = flow.request.path.split("?")[0].lower()

    # Redirects are never downloads - the .tar.gz in a 302's URL is a false positive.
    if 300 <= resp.status_code < 400:
        return

    is_dl = (
        "attachment" in cd.lower()
        or ctype in DOWNLOAD_TYPES
        or any(path.endswith(e) for e in DOWNLOAD_EXTS)
    )
    if not is_dl:
        return

    rec = {
        "kind": "download_candidate",
        "method": flow.request.method,
        "url": flow.request.pretty_url[:500],
        "content_type": ctype,
        "content_disposition": cd,
        "content_length": clen,
        "status": resp.status_code,
        "sec_fetch_dest": flow.request.headers.get("sec-fetch-dest", ""),
        "sec_fetch_mode": flow.request.headers.get("sec-fetch-mode", ""),
        "has_cookie": bool(flow.request.headers.get("cookie")),
        "client": _client_fingerprint(flow.client_conn),
        "armed": ARM_204,
    }
    _log(rec)

    ctx.log.warn("=" * 72)
    ctx.log.warn(f"[SDM-PROBE] *** DOWNLOAD DETECTED (pre-body) ***")
    ctx.log.warn(f"[SDM-PROBE] {flow.request.method} {flow.request.pretty_url[:160]}")
    ctx.log.warn(f"[SDM-PROBE] type={ctype!r} disp={cd!r} len={clen} status={resp.status_code}")
    ctx.log.warn(f"[SDM-PROBE] sec-fetch-dest={rec['sec_fetch_dest']!r} cookie={rec['has_cookie']}")
    ctx.log.warn("=" * 72)

    if ARM_204:
        # THE moment of truth: kill the body, tell Safari "nothing happened".
        flow.response = http.Response.make(204, b"", {})
        ctx.log.warn("[SDM-PROBE] --> replaced with 204 No Content. Safari should stay put.")
