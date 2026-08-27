"""
Strategy bake-off for stopping a Safari download cleanly.

Strategy A (make_204) crashed mitmproxy: replacing flow.response wholesale in
responseheaders tears down the upstream connection while its body is still
pending -> "OSError: Server has been shut down" -> Safari reports
"the server unexpectedly dropped the connection".

The variants below try to hand Safari a clean "nothing to see here" without
breaking the proxy's state machine.
"""
import os
from mitmproxy import http, ctx

STRATEGY = os.environ.get("SDM_STRATEGY", "make_204")
MARK = "/Users/aintyourcupoftea/Development/SafariDownloadManager/logs/last_action.txt"

DOWNLOAD_TYPES = (
    "application/octet-stream", "application/zip", "application/x-apple-diskimage",
    "application/x-msdownload", "application/gzip", "application/x-gzip",
    "application/x-tar", "application/x-7z-compressed", "application/x-iso9660-image",
)
DOWNLOAD_EXTS = (".dmg", ".zip", ".pkg", ".iso", ".tar", ".gz", ".tgz", ".7z", ".exe", ".bin", ".mp4")


def running(*_):
    ctx.log.warn(f"[SDM] strategy={STRATEGY}")


def _is_download(flow):
    r = flow.response
    if r is None or 300 <= r.status_code < 400:
        return False
    cd = (r.headers.get("content-disposition", "") or "").lower()
    ctype = (r.headers.get("content-type", "") or "").split(";")[0].strip().lower()
    path = flow.request.path.split("?")[0].lower()
    return ("attachment" in cd
            or ctype in DOWNLOAD_TYPES
            or any(path.endswith(e) for e in DOWNLOAD_EXTS))


def responseheaders(flow: http.HTTPFlow):
    if not _is_download(flow):
        return

    r = flow.response
    name = (r.headers.get("content-disposition", "") or "")
    ctx.log.warn(f"[SDM] INTERCEPT {flow.request.pretty_url[:90]} :: {name[:60]}")
    with open(MARK, "w") as f:
        f.write(f"{STRATEGY}|{flow.request.pretty_url[:200]}\n")

    if STRATEGY == "make_204":
        # A: known-broken baseline.
        flow.response = http.Response.make(204, b"", {})

    elif STRATEGY == "mutate_204":
        # B: mutate in place, discard body as it arrives. Keeps the state
        # machine intact because mitmproxy still "reads" the response.
        r.status_code = 204
        r.reason = "No Content"
        for h in list(r.headers.keys()):
            del r.headers[h]
        r.stream = lambda chunks: b""

    elif STRATEGY == "mutate_200_empty":
        # C: 200 with a zero-length body.
        r.status_code = 200
        r.reason = "OK"
        for h in list(r.headers.keys()):
            del r.headers[h]
        r.headers["content-length"] = "0"
        r.headers["content-type"] = "text/plain"
        r.stream = lambda chunks: b""

    elif STRATEGY == "mutate_204_keepenc":
        # D: 204 but leave framing headers alone except length.
        r.status_code = 204
        r.reason = "No Content"
        for h in ("content-disposition", "content-type", "content-length"):
            if h in r.headers:
                del r.headers[h]
        r.stream = lambda chunks: b""

    ctx.log.warn(f"[SDM] applied {STRATEGY}")
