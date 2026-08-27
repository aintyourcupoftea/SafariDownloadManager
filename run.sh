#!/bin/bash
# Start SafariDownloadManager interception. Leave this running.
# NEVER kill mitmdump mid-download: that detaches the macOS NEAppProxyProvider
# binding and silently stops all capture until Safari + mitmdump are restarted.
cd "$(dirname "$0")"
IGN=()
while read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  IGN+=(--ignore-hosts "$line")
done < config/bypass.txt

exec mitmdump --mode local:Safari -s addon/sdm.py \
  --set http3=false \
  "${IGN[@]}" \
  --set termlog_verbosity=warn
