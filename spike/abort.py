"""Confirm the body really streams, then try to abort upstream early.

The client already has a complete 204 (no body expected), so killing the flow
on the first chunk should only tear down the SERVER side. If Safari stays calm
we get interception with near-zero wasted bandwidth.
"""
import os, time
from mitmproxy import http, ctx

MODE = os.environ.get("SDM_ABORT", "measure")   # measure | kill
OUT = "/Users/aintyourcupoftea/Development/SafariDownloadManager/logs/abort.txt"

def _log(m):
    ctx.log.warn(m)
    with open(OUT, "a") as f:
        f.write(m + "\n")

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
    total = int(r.headers.get("content-length", "0") or 0)
    _log(f"[AB] mode={MODE} intercept content-length={total}")

    st = {"n": 0, "t0": time.time(), "killed": False, "last": 0}

    def discard(chunks):
        st["n"] += len(chunks)
        # progress every ~2 MB so we can SEE whether bytes really flow
        if st["n"] - st["last"] >= 2_000_000:
            st["last"] = st["n"]
            _log(f"[AB] pulled {st['n']//1000000}MB in {time.time()-st['t0']:.1f}s")
        if MODE == "kill" and not st["killed"] and st["n"] > 262144:
            st["killed"] = True
            _log(f"[AB] killing flow after {st['n']} bytes")
            try:
                flow.kill()
            except Exception as e:
                _log(f"[AB] kill failed: {e!r}")
        return b""

    r.status_code = 204
    r.reason = "No Content"
    for h in list(r.headers.keys()):
        del r.headers[h]
    r.stream = discard
