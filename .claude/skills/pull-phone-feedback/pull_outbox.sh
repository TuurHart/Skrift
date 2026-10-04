#!/bin/zsh
# Pull the FeedbackKit outbox off the phone and digest it (Q308).
# usage: pull_outbox.sh [dest-dir] [bundle-id]
#   dest-dir   default /tmp/skrift-feedback-outbox
#   bundle-id  default com.skrift.mobile.dev
# Needs the phone connected and unlocked. Writes <dest>/outbox/ and <dest>/DIGEST.md.
set -eu
UDID="${SKRIFT_UDID:-00008110-001208C902EA201E}"
DEST="${1:-/tmp/skrift-feedback-outbox}"
BUNDLE="${2:-com.skrift.mobile.dev}"
HERE="${0:A:h}"

rm -rf "$DEST/outbox"
mkdir -p "$DEST"
xcrun devicectl device copy from --device "$UDID" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --source "Library/Application Support/FeedbackKit/outbox" --destination "$DEST/outbox"
# devicectl may nest the folder one level (outbox/outbox); use whichever holds the .json files.
DIR="$DEST/outbox"
[ -n "$(ls "$DIR"/*.json 2>/dev/null)" ] || { [ -d "$DIR/outbox" ] && DIR="$DIR/outbox"; }
echo "pulled: $(ls "$DIR"/*.json 2>/dev/null | wc -l | tr -d ' ') note(s) in $DIR"
python3 "$HERE/outbox_digest.py" "$DIR" --out "$DEST/DIGEST.md"
echo "digest: $DEST/DIGEST.md"
