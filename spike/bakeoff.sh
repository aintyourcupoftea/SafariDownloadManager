#!/bin/bash
# Automated Safari oracle: does the strategy stop the download AND keep Safari calm?
cd /Users/aintyourcupoftea/Development/SafariDownloadManager
STRAT="$1"
DL_URL="https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0.tar.gz"
BASE="https://example.com/"

pkill -f "mitmdump --mode local" 2>/dev/null; sleep 2
rm -f ~/Downloads/aria2-1.37.0.tar ~/Downloads/aria2-1.37.0.tar.gz
rm -rf ~/Downloads/aria2-1.37.0.tar.gz.download 2>/dev/null
: > logs/last_action.txt

SDM_STRATEGY="$STRAT" mitmdump --mode local:Safari -s spike/strategies.py \
  --ignore-hosts 'mask\.icloud\.com' --set termlog_verbosity=warn \
  > "logs/bake_${STRAT}.log" 2>&1 &
sleep 5

# park Safari on a known page
osascript -e "tell application \"Safari\" to set URL of current tab of window 1 to \"$BASE\"" >/dev/null 2>&1
sleep 4
# now navigate to the download
osascript -e "tell application \"Safari\" to set URL of current tab of window 1 to \"$DL_URL\"" >/dev/null 2>&1
sleep 12

TITLE=$(osascript -e 'tell application "Safari" to get name of current tab of window 1' 2>/dev/null)
URL=$(osascript -e 'tell application "Safari" to get URL of current tab of window 1' 2>/dev/null | cut -c1-60)
INTERCEPTED=$(grep -c "applied" "logs/bake_${STRAT}.log" 2>/dev/null || echo 0)
CRASHED=$(grep -c "has crashed" "logs/bake_${STRAT}.log" 2>/dev/null || echo 0)
LEAKED="no"; ls ~/Downloads/ 2>/dev/null | grep -qiE "aria2" && LEAKED="YES"

echo "STRATEGY=$STRAT"
echo "  intercepted=$INTERCEPTED  crashed=$CRASHED  leaked=$LEAKED"
echo "  tab_title='$TITLE'"
echo "  tab_url='$URL'"
pkill -f "mitmdump --mode local" 2>/dev/null
