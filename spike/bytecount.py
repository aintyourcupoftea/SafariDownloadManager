"""Does the winning 204 strategy still pull the body from upstream?
Count every byte that reaches the discard callback."""
import time
from mitmproxy import http, ctx

STATE = {"bytes": 0, "t0": None, "url": None, "done": False}
OUT = "/Users/aintyourcupoftea/Development/SafariDownloadManager/logs/bytecount.txt"

def _is_dl(flow):
    r = flow.response
    if r is None or 300 <= r.status_code < 400:
        return False
    cd = (r.headers.get("content-disposition", "") or "").lower()
    ct = (r.headers.get("content-type", "") or "").split(";")[0].lower()
    return "attachment" in cd or ct in (
        "application/octet-stream", "application/x-apple-diskimage",
        "application/x-iso9660-image", "application/zip")

def responseheaders(flow: http.HTTPFlow):
    if not _is_dl(flow):
        return
    r = flow.response
    total = r.headers.get("content-length", "?")
    STATE.update(bytes=0, t0=time.time(), url=flow.request.pretty_url[:70], done=False)
    ctx.log.warn(f"[BC] intercept, upstream content-length={total}")

    def discard(chunks):
        STATE["bytes"] += len(chunks)
        return b""

    r.status_code = 204
    r.reason = "No Content"
    for h in list(r.headers.keys()):
        del r.headers[h]
    r.stream = discard
    ctx.log.warn(f"[BC] 204 applied, watching for upstream bytes...")

def response(flow: http.HTTPFlow):
    if STATE["t0"] and not STATE["done"]:
        STATE["done"] = True
        dt = time.time() - STATE["t0"]
        msg = f"[BC] RESULT discarded_bytes={STATE['bytes']} elapsed={dt:.2f}s"
        ctx.log.warn(msg)
        with open(OUT, "a") as f:
            f.write(msg + "\n")
