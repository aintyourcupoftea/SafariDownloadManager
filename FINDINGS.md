# Phase 0 spike — RESULT: PASSED (2026-08-27)

Verified on macOS 26.6.2 Tahoe / arm64 / Safari 26.6.2 / mitmproxy 12.2.3.

## The gate

| # | Question | Result |
|---|----------|--------|
| 1 | Do flows appear in `--mode local`? | **Yes** |
| 2 | What scope string matches Safari? | **`--mode local:Safari`** |
| 3 | Does TLS decrypt in Safari? | **Yes** |
| 4 | Is `Content-Disposition` visible pre-body? | **Yes**, in `responseheaders` |
| 5 | Does a 204 stop Safari downloading? | **Yes — nothing hit `~/Downloads`** |

## Key findings

**`--mode local:Safari` is the correct scope, and it works despite Safari not making
its own connections.** Safari's traffic is issued by `com.apple.WebKit.Networking`
(two instances were running, both `ppid=1`). The mitmproxy redirector resolves the
*responsible app*, not the raw process — so the intuitive spec matches. Confirmed by
capturing `example.com`, `github.com`, and `release-assets.githubusercontent.com`
from Safari while non-Safari traffic was left alone.

**No sudo, no System keychain.** `security add-trusted-cert -r trustRoot -k
~/Library/Keychains/login.keychain-db` at *user* level is honoured by Safari.
The `-d` (admin) variant is unnecessary. This keeps the MITM root scoped to one
user and makes teardown a one-liner.
Reverse with: `security delete-certificate -c mitmproxy ~/Library/Keychains/login.keychain-db`

**The addon API exposes no process identity.** `client_conn` gives
`peername = ('127.0.0.1', 0)` — no pid, no name. Every attribute was enumerated;
there is nothing. Process filtering must therefore happen in the redirector via
`--mode local:<spec>`, never in addon logic. Plan B's "look up the PID in the
addon" is *not* available here — noted in case we ever fall back.

**Redirect chains work end to end.** `github.com` 302 -> presigned
`release-assets.githubusercontent.com` was followed, and the final response carried
`content-disposition: attachment; filename=aria2-1.37.0.tar.gz`,
`application/octet-stream`, `content-length: 3904613`. The classifier sees the
*final* response with the real filename, which is exactly what the downloader needs.

**Classifier bug found and fixed:** the 302 itself was matched as a download because
its URL path ends in `.tar.gz`. 3xx responses must be skipped explicitly.

**Safari mangles gzip.** Left alone, Safari saved the 3,904,613-byte `.tar.gz` as a
20 MB decompressed `.tar`. Our downloader must not do this — an independent
correctness argument for the whole project.

## Blockers / constraints for Phase 1

**iCloud Private Relay must be OFF.** `/usr/libexec/networkserviceproxy` is running.
Every TLS error in the logs was `mask.icloud.com` — Private Relay is pinned and
rejects our MITM. Right now that failure *accidentally* helps us (Safari falls back
to direct connections we can then intercept), but it produces a retry storm and is
fragile. It cannot simply be added to `--ignore-hosts`: if Private Relay succeeds,
Safari's traffic is tunnelled and we see nothing at all.
-> System Settings -> Apple Account -> iCloud -> Private Relay -> Off.

**Pinned non-Safari apps are unaffected**, but during the *unscoped* run
`api.torbox.app` failed with "client does not trust the proxy's certificate".
Confirms why scoping is mandatory, and confirms scoping works.

**Not yet tested:** HTTP/3/QUIC coverage, `<a download>` on renderable MIME,
blob:/data:, popup/new-tab 204 behaviour, one-time-link re-request.

---

# Phase 1 — RESULT: WORKING

## The architecture changed twice, both times driven by evidence

**Attempt 1 — replace the response in `responseheaders`.** Crashed:
`OSError: Server has been shut down`. Safari showed "the server unexpectedly
dropped the connection". Replacing `flow.response` wholesale tears down the
upstream connection while its body is pending.

**Attempt 2 — mutate the response in place to 204, discard the body.** Worked
for a 3.9 MB file (Safari stayed put, no crash). Failed for 159 MB: mitmproxy
holds the *client* stream open until the *upstream* body finishes, so Safari sat
waiting on a 204 it had already received, gave up at 72 MB, and sent
`ConnectionTerminated error_code:11` — which killed our transfer too.

Teeing the body to disk did not save this. The tee is hostage to Safari's
patience, so **any design that lets the upstream body run inside the flow is
bounded by how long Safari will wait.** That killed tee-through-proxy.

**Attempt 3 — probe in the `request` hook. This is the one.**
Decide *before* the request reaches the server: issue our own
`Range: bytes=0-0` request, inspect the headers, and if it is a download,
short-circuit by setting `flow.response` in the **request** hook. No upstream
body is ever pending, so the 204 is clean and instant, and the real download is
handed to aria2 completely detached from the proxy flow.

## Verified

| Case | Safari | File | Bytes |
|---|---|---|---|
| GitHub `.tar.gz`, `Content-Disposition` + 302 | stayed put | `aria2-1.37.0.tar.gz` | 3,904,613 exact |
| Mozilla `.dmg`, no disposition, 302 | stayed put | `Firefox 154.0.1.dmg` | 159,494,566 exact |
| news.ycombinator.com | loads normally | — | — |
| en.wikipedia.org | loads normally | — | — |
| apple.com | loads normally *after* bypass list | — | — |

Zero crashes. Zero false interceptions of ordinary pages. aria2 sustained
23 MiB/s. The GitHub file came down as the **original gzip** — Safari left to
itself decompressed it into a 20 MB `.tar`.

## Two operational hazards

**Killing mitmdump detaches the redirector, silently.** Six restarts in a row
during testing left `NEAppProxyProvider` unbound: mitmdump ran happily and
reported *zero* flows, with no error anywhere. Recovery is quit Safari ->
restart proxy -> relaunch Safari. This is why behaviour is switched through
`state/STRATEGY`, re-read on every call, instead of by restarting.

**`apple.com` breaks under MITM** ("This Connection Is Not Private"). Pinned and
CT-strict hosts need TLS passthrough — `config/bypass.txt`.

## Corrections to earlier assumptions

- `timeout(1)` does not exist on macOS; two early tests silently did nothing.
- Safari's HTTP/3 *is* captured by the redirector, but mitmproxy 12.2.3's QUIC
  layer throws `IndexError` in `_stream_layers.py`. `--set http3=false` avoids
  it and Safari falls back to TCP. So HTTP/3 was never the cause of the
  zero-flow condition — that was the detached redirector.

---

# Phase 1 hardening — a safety bug found in review

The probe was firing a real, cookie-carrying `GET` at **every** top-level
navigation. On a `GET`-based action URL — unsubscribe, logout, confirm-email,
delete — that executes the side effect, once from the probe and again from
Safari's real request. During testing HN, Wikipedia and apple.com were each hit
twice. This was the one defect in the build capable of causing damage rather
than inconvenience.

**Fix:** the probe is gated behind `_looks_downloadable()` — it only fires at
URLs whose path already ends in a known file extension. Verified: browsing four
ordinary pages, including query-string URLs, fires **zero** probes.

**The gate created a coverage hole, so the fallback was widened.** Mozilla's
`download.mozilla.org/?product=…` has neither a file extension nor a
`Content-Disposition`, so it now escaped the probe entirely. The
`responseheaders` fallback was relaxed from "attachment only" to the full
classifier, which matches on content-type. Re-verified byte-exact.

Notably the fallback handles a 159 MB file with Safari still staying put: above
`FALLBACK_MAX_DRAIN` it hands off to aria2 and then `flow.kill()`s rather than
draining a body it would throw away. Killing *after* mutating the response to
204 turns out to be clean — unlike replacing `flow.response` outright.

## Final verification

| Path | Case | Safari | Bytes |
|---|---|---|---|
| probe | GitHub `.tar.gz` | stayed put | 3,904,613 exact |
| fallback | Mozilla `.dmg`, no ext, no disposition | stayed put | 159,494,566 exact |
| — | HN / Wikipedia / DuckDuckGo / apple.com | load normally | 0 probes fired |

`sdm queue` reports real progress off the filesystem; `sdm misses` reports any
`*.download` bundle Safari creates, which is the only detector for the silent
gaps. Zero crashes.

## Still untested — do not assume these work

- **Cookie-gated downloads.** Both test files are public. `_handoff` forwards
  `cookie`/`authorization` to aria2 but this has never been exercised against a
  real logged-in download. Failure signature: an HTML login page saved under a
  `.zip` name, or a size mismatch.
- POST-initiated downloads, `<a download>` on renderable types, `blob:`/`data:`.
