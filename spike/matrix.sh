#!/bin/bash
cd /Users/aintyourcupoftea/Development/SafariDownloadManager
oracle () {  # PASS only if BOTH title and url are still the base page
  T=$(osascript -e 'tell application "Safari" to get name of current tab of window 1' 2>/dev/null)
  U=$(osascript -e 'tell application "Safari" to get URL of current tab of window 1' 2>/dev/null)
  if [[ "$T" == "Example Domain" && "$U" == https://example.com/* ]]; then echo "STAYED_PUT"; else echo "NAVIGATED_AWAY[title=$T]"; fi
}
park () { osascript -e 'tell application "Safari" to set URL of current tab of window 1 to "https://example.com/"' >/dev/null 2>&1; sleep 4; }
go   () { osascript -e "tell application \"Safari\" to set URL of current tab of window 1 to \"$1\"" >/dev/null 2>&1; }

test_dl () {
  NAME="$1"; URL="$2"; EXPECT_FILE="$3"; EXPECT_SIZE="$4"
  rm -f ~/Downloads/"$EXPECT_FILE" ~/Downloads/*.aria2 2>/dev/null
  park
  BEFORE=$(date +%s)
  go "$URL"
  sleep 14
  echo "TEST: $NAME"
  echo "  safari:    $(oracle)"
  echo "  intercept: $(grep -c 'PROBE-INTERCEPT' logs/agent.log)"
  # wait for aria2 up to 60s
  for i in $(seq 1 30); do [ -f ~/Downloads/"$EXPECT_FILE" ] && ! ls ~/Downloads/*.aria2 >/dev/null 2>&1 && break; sleep 2; done
  if [ -f ~/Downloads/"$EXPECT_FILE" ]; then
    SZ=$(stat -f%z ~/Downloads/"$EXPECT_FILE")
    if [ "$SZ" = "$EXPECT_SIZE" ]; then echo "  file:      OK $EXPECT_FILE ($SZ bytes, exact)"; else echo "  file:      SIZE MISMATCH got=$SZ want=$EXPECT_SIZE"; fi
  else
    echo "  file:      MISSING (expected $EXPECT_FILE)"; ls ~/Downloads/ | tail -3
  fi
}
