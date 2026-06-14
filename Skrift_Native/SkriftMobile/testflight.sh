#!/usr/bin/env bash
# One-shot TestFlight upload for Skrift — internal testers, NO App Store review.
# Replicates glot-study/echo: xcodebuild archive (Release) → -exportArchive with
# ExportOptions.plist (method=app-store-connect, destination=upload → auto-uploads)
# authenticated by an App Store Connect API key.
#
# PREREQS (one-time, NOT code — see NEXT_CHAT_HANDOFF.md "TestFlight"):
#   1. An ASC app record for com.skrift.mobile (create in App Store Connect; instant).
#   2. An App Store Distribution cert + profiles for com.skrift.mobile{,.share,.widget}
#      (-allowProvisioningUpdates tries to mint them; if the API key can't, create them
#      once in Xcode / ASC — same team 9W82X49JZS as glot-echo, so they may already exist).
#   3. The ASC API key (.p8) on disk + its key id + issuer id.
#
# RUN:
#   export ASC_KEY_PATH=~/.asc-api/key.p8
#   export ASC_KEY_ID=XXXXXXXXXX
#   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   ./testflight.sh
set -euo pipefail
cd "$(dirname "$0")"

: "${ASC_KEY_PATH:?set ASC_KEY_PATH to the .p8 file}"
: "${ASC_KEY_ID:?set ASC_KEY_ID (10-char key id from ASC → Users & Access → Integrations → Keys)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (issuer UUID from the same page)}"

echo "▶ regenerating project…"
xcodegen generate

echo "▶ archiving Release (com.skrift.mobile)…"
xcodebuild archive \
  -project SkriftMobile.xcodeproj -scheme SkriftMobile -configuration Release \
  -derivedDataPath build-archive -archivePath build-archive/SkriftMobile.xcarchive \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=9W82X49JZS CODE_SIGN_STYLE=Automatic

echo "▶ exporting + uploading to App Store Connect (TestFlight)…"
xcodebuild -exportArchive \
  -archivePath build-archive/SkriftMobile.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build-archive/export \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "✅ Uploaded. It appears in App Store Connect → TestFlight after ~5–15 min processing."
echo "   Internal testers (your team, up to 100) can install immediately — no review."
