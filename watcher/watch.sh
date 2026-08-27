#!/bin/bash
# Coverage-miss detector.
# A *.download bundle in ~/Downloads means SAFARI downloaded something, i.e.
# our interception missed it. That is the only way we learn about the silent
# gaps (HTTP/3, <a download> on renderable types, blob:/data:, bypassed hosts).
R="/Users/aintyourcupoftea/Development/SafariDownloadManager"
MISS="$R/logs/misses.log"
seen=""
while true; do
  for d in "$HOME/Downloads"/*.download; do
    [ -e "$d" ] || continue
    b=$(basename "$d")
    case "$seen" in *"|$b|"*) continue ;; esac
    seen="$seen|$b|"
    url=$(plutil -extract DownloadEntryURL raw "$d/Info.plist" 2>/dev/null | head -1)
    printf '%s MISS %s  url=%s\n' "$(date '+%F %T')" "$b" "${url:-unknown}" >> "$MISS"
  done
  sleep 5
done
