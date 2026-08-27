# safari-download-manager

**IDM-style download interception for Safari on macOS.** Click a download in
Safari and it goes to a parallel-connection download engine instead of Safari —
and Safari stays on the page it was on.

```
brew tap aintyourcupoftea/tap
brew install safari-download-manager
sdm setup
sdm on
```

## Why this didn't exist

Safari implements neither `browser.downloads` nor blocking `webRequest`. An
extension cannot see the download decision and cannot cancel the request, which
is where every IDM-for-Safari attempt has died. This works one layer lower.

## How it works

```
Safari ──▶ interception proxy ──▶ internet
             (scoped to Safari alone; nothing else is touched)
                   │
     URL looks like a file? ──no──▶ pass through untouched
                   │ yes                    │
            probe it (1 byte)        if the RESPONSE turns out
                   │                  to be a download, the
             download?                fallback path catches it
                   │ yes
                   ├──▶ aria2 daemon (8 conns, resumable, RPC-controlled)
                   └──▶ Safari gets 204 No Content ──▶ stays on the page
```

Deciding in the **request** hook is the crux: Safari's request never reaches the
server, so the `204` has no pending body and lands instantly. Deciding later
does not work — Safari gives up partway through a large file because it is
waiting on a body the proxy hasn't finished draining.

**The probe is deliberately gated.** It is a real HTTP request carrying your
cookies, so it only fires at URLs that already look like files. Probing every
navigation would double-fire side-effecting `GET` endpoints — unsubscribe links,
logout, confirm-email. Ordinary browsing fires zero probes.

## Commands

```
sdm setup       first run: CA, services, launch agents
sdm on | off    toggle interception
sdm status      proxy / engine / redirector health
sdm doctor      full diagnostics
sdm queue       current downloads
sdm watch       live updating view
sdm misses      downloads that escaped interception
sdm uninstall   remove services, untrust the CA
```

## What it does to your Mac

- Generates a local CA and trusts it in your **login keychain only** — no sudo,
  no System keychain. `sdm uninstall` removes it.
- Uses mitmproxy's signed network extension, scoped to Safari. No other app's
  traffic is decrypted.
- Runs two launch agents (proxy, download engine) plus a coverage watcher.

## Known gaps

| Gap | Why |
|---|---|
| `<a download>` on a renderable type | the proxy sees `image/png` and cannot see the `download` attribute |
| `blob:` / `data:` URLs | never touch the network |
| HTTP/3 | mitmproxy's QUIC layer is unstable; we force TCP |
| Pinned hosts (`config/bypass.txt`) | they reject a local root — site correctness wins |
| POST-initiated downloads | the probe only handles GET/HEAD |

`sdm misses` reports anything that slipped through, so gaps are visible rather
than silent.

## Operational note

Never kill the proxy mid-download. It detaches the macOS `NEAppProxyProvider`
binding and silently stops all capture. `sdm status` reports
`redirector NOT attached`; `sdm restart` plus a Safari relaunch fixes it.

## License

MIT
