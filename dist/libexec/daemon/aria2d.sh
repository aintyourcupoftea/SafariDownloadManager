#!/bin/bash
# Long-lived aria2 with JSON-RPC. One daemon for all downloads: real progress,
# pause/resume/cancel, correct control-file lifecycle, and a global connection
# budget so we do not trigger HTTP 429 by hammering a single host.
set -euo pipefail
: "${SDM_HOME:?SDM_HOME not set}"
ARIA2="${SDM_ARIA2:-$(command -v aria2c)}"
PORT="${SDM_RPC_PORT:-6800}"
DL="${SDM_DOWNLOAD_DIR:-$HOME/Downloads}"
mkdir -p "$SDM_HOME/state/aria2" "$SDM_HOME/logs"
touch "$SDM_HOME/state/aria2/session.txt"
SECRET="$(cat "$SDM_HOME/state/rpc.secret")"

exec "$ARIA2" \
  --enable-rpc --rpc-listen-all=false --rpc-listen-port="$PORT" --rpc-secret="$SECRET" \
  --dir="$DL" \
  --continue=true --auto-file-renaming=true --allow-overwrite=false \
  --max-concurrent-downloads="${SDM_MAX_CONCURRENT:-4}" \
  --max-connection-per-server="${SDM_CONNECTIONS:-8}" \
  --split="${SDM_CONNECTIONS:-8}" --min-split-size=4M \
  --max-tries=5 --retry-wait=3 --connect-timeout=15 --timeout=30 \
  --file-allocation=none --summary-interval=0 --console-log-level=warn \
  --save-session="$SDM_HOME/state/aria2/session.txt" \
  --input-file="$SDM_HOME/state/aria2/session.txt" \
  --save-session-interval=20 \
  --force-save=false \
  --log="$SDM_HOME/logs/aria2d.log" --log-level=notice
