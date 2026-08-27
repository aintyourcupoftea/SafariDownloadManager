"""Live download status straight from the aria2 daemon."""
import json, os, sys, urllib.request
R = "/Users/aintyourcupoftea/Development/SafariDownloadManager"

def rpc(method, params=None):
    secret = open(f"{R}/state/rpc.secret").read().strip()
    body = json.dumps({"jsonrpc": "2.0", "id": "s", "method": method,
                       "params": [f"token:{secret}", *(params or [])]}).encode()
    req = urllib.request.Request("http://127.0.0.1:6800/jsonrpc", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=6) as r:
        return json.load(r).get("result")

def human(n):
    n = float(n)
    for u in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024: return f"{n:.1f}{u}"
        n /= 1024
    return f"{n:.1f}PB"

def eta(done, total, speed):
    if not speed or total <= done: return "-"
    s = int((total - done) / speed)
    h, m = divmod(s // 60, 60)
    return f"{h}h{m:02d}m" if h else (f"{m}m{s%60:02d}s" if m else f"{s}s")

def name_of(d):
    fs = d.get("files") or []
    if fs and fs[0].get("path"):
        return os.path.basename(fs[0]["path"])
    return (d.get("gid") or "?")[:8]

def main():
    FIELDS = ["gid","status","totalLength","completedLength","downloadSpeed","files","errorMessage","connections"]
    try:
        rows = (rpc("aria2.tellActive", [FIELDS]) or []) \
             + (rpc("aria2.tellWaiting", [0, 20, FIELDS]) or []) \
             + (rpc("aria2.tellStopped", [0, 20, FIELDS]) or [])
    except Exception as e:
        print(f"aria2 daemon unreachable: {e}"); return (1)
    
    if not rows:
        print("  (no downloads)"); return (0)
    
    W = 42
    for d in rows:
        tot = int(d.get("totalLength") or 0)
        got = int(d.get("completedLength") or 0)
        spd = int(d.get("downloadSpeed") or 0)
        pct = (100 * got // tot) if tot else 0
        st = d.get("status", "?")
        bar_w = 22
        filled = (pct * bar_w) // 100 if tot else 0
        bar = "█" * filled + "░" * (bar_w - filled)
        nm = name_of(d)
        nm = nm if len(nm) <= W else nm[:W-1] + "…"
        tail = f"{human(spd)}/s  ETA {eta(got,tot,spd)}  ({d.get('connections','0')} conns)" if st == "active" \
               else (d.get("errorMessage") or st)
        print(f"{nm:<{W}} {bar} {pct:>3}%  {human(got):>8}/{human(tot):<8} {tail}")
    

if __name__ == "__main__":
    main()
