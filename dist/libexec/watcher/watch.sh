#!/bin/bash
# Coverage-miss detector. A *.download bundle means SAFARI downloaded something,
# i.e. interception missed it. This is the only way we learn about silent gaps
# (HTTP/3, <a download> on renderable types, blob:/data:, bypassed hosts).
set -uo pipefail
: "${SDM_HOME:?SDM_HOME not set}"
DL="${SDM_DOWNLOAD_DIR:-$HOME/Downloads}"
MISS="$SDM_HOME/logs/misses.log"
mkdir -p "$SDM_HOME/logs"
seen=""
while true; do
  for d in "$DL"/*.download; do
    [ -e "$d" ] || continue
    b=$(basename "$d")
    case "$seen" in *"|$b|"*) continue ;; esac
    seen="$seen|$b|"
    url=$(plutil -extract DownloadEntryURL raw "$d/Info.plist" 2>/dev/null | head -1)
    printf '%s MISS %s url=%s\n' "$(date '+%F %T')" "$b" "${url:-unknown}" >> "$MISS"
  done
  sleep 5
done
