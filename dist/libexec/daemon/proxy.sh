#!/bin/bash
# Safari-scoped interception proxy.
# NEVER kill this mid-download: it detaches the macOS NEAppProxyProvider binding
# and silently stops ALL capture until Safari and this process both restart.
set -euo pipefail
: "${SDM_HOME:?SDM_HOME not set}"
: "${SDM_LIBEXEC:?SDM_LIBEXEC not set}"
MITM="${SDM_MITMDUMP:-$(command -v mitmdump)}"
BYPASS="$SDM_HOME/config/bypass.txt"

IGN=()
if [ -f "$BYPASS" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    IGN+=(--ignore-hosts "$line")
  done < "$BYPASS"
fi

exec "$MITM" \
  --mode "local:${SDM_TARGET_APP:-Safari}" \
  -s "$SDM_LIBEXEC/addon/sdm_addon.py" \
  --set http3=false \
  "${IGN[@]}" \
  --set termlog_verbosity=warn
