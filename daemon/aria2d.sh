#!/bin/bash
# Single long-lived aria2 with JSON-RPC. One daemon instead of a process per
# download: gives real progress, pause/resume/cancel, correct control-file
# lifecycle, and a global connection budget so we stop triggering HTTP 429.
R="/Users/aintyourcupoftea/Development/SafariDownloadManager"
SECRET="$(cat "$R/state/rpc.secret")"
mkdir -p "$R/state/aria2"
exec /opt/homebrew/bin/aria2c \
  --enable-rpc \
  --rpc-listen-all=false \
  --rpc-listen-port=6800 \
  --rpc-secret="$SECRET" \
  --dir="$HOME/Downloads" \
  --continue=true \
  --auto-file-renaming=true \
  --allow-overwrite=false \
  --max-concurrent-downloads=4 \
  --max-connection-per-server=8 \
  --split=8 \
  --min-split-size=4M \
  --max-tries=5 \
  --retry-wait=3 \
  --connect-timeout=15 \
  --timeout=30 \
  --file-allocation=none \
  --summary-interval=0 \
  --console-log-level=warn \
  --save-session="$R/state/aria2/session.txt" \
  --input-file="$R/state/aria2/session.txt" \
  --save-session-interval=20 \
  --force-save=false \
  --log="$R/logs/aria2d.log" \
  --log-level=notice
