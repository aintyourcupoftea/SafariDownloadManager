"""Classifier regression tests.

Every case here came from something that actually happened, not from
imagination. The f.txt case is Google's autocomplete endpoint, which was
"downloaded" 13 times before the size floor was fixed.
"""
import importlib.util, sys, types, os

def load_addon():
    m = types.ModuleType("mitmproxy"); http = types.ModuleType("mitmproxy.http")
    ctx = types.ModuleType("mitmproxy.ctx")
    class _L:
        def warn(self, *a, **k): pass
    ctx.log = _L(); http.HTTPFlow = object; http.Response = object
    sys.modules.update({"mitmproxy": m, "mitmproxy.http": http, "mitmproxy.ctx": ctx})
    m.http = http; m.ctx = ctx
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    spec = importlib.util.spec_from_file_location("sdm", os.path.join(here, "addon", "sdm.py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    return mod

CASES = [
    ("Google Suggest f.txt (attachment, no length, .txt)",
     {"content-disposition": 'attachment; filename="f.txt"', "content-type": "application/json"},
     "https://www.google.com/complete/search?q=git", 0, False),
    ("tiny chunked octet-stream beacon",
     {"content-type": "application/octet-stream"}, "https://ads.example.com/beacon", 0, False),
    ("small octet-stream with known length",
     {"content-type": "application/octet-stream"}, "https://x.example.com/ping", 900, False),
    ("Firefox dmg by content-type",
     {"content-type": "application/x-iso9660-image"},
     "https://cdn.mozilla.net/pub/Firefox%20154.0.1.dmg", 159494566, True),
    ("GitHub release asset, presigned url, attachment",
     {"content-disposition": "attachment; filename=aria2-1.37.0.tar.gz",
      "content-type": "application/octet-stream"},
     "https://release-assets.githubusercontent.com/x?token=1", 3904613, True),
    ("chunked attachment with a real extension",
     {"content-disposition": 'attachment; filename="movie.mkv"',
      "content-type": "application/octet-stream"},
     "https://cdn.example.com/stream", 0, True),
    ("ordinary html page",
     {"content-type": "text/html; charset=utf-8"}, "https://news.ycombinator.com/", 4200, False),
    ("json api response",
     {"content-type": "application/json"}, "https://api.example.com/v1/items", 20000, False),
    ("large blob, random name, no extension",
     {"content-type": "application/octet-stream"},
     "https://t.example.com/cgr3uv7kdjqeo4r7m9588kd59", 150220, True),
]

def main():
    sdm = load_addon()
    fails = 0
    print(f"{'case':<52}{'want':>6}{'got':>6}")
    for name, h, url, clen, want in CASES:
        got = sdm._classify(h, url, clen)
        if got != want:
            fails += 1
        print(f"{name:<52}{str(want):>6}{str(got):>6}  {'ok' if got == want else 'FAIL'}")
    print(f"\n{len(CASES) - fails}/{len(CASES)} passed")
    return 1 if fails else 0

if __name__ == "__main__":
    sys.exit(main())
