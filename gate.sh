#!/bin/zsh
# gate.sh — "is Skrift still alive?" in one command. Cheap on purpose: the Mac unit suite
# (MLX-free, ~3 min), which also seeds the synthetic corpus and proves the rate→row
# invariant over every note. Exit 0 = green. The phone suite and the full MLX build are
# NOT here (10+ min each); run them before a device push, not per work item.
#
# Usage: ./gate.sh            (from the repo root)
#        ./gate.sh --full     (also the phone unit suite on the iPhone 17 sim)
set -u
cd "$(dirname "$0")"
LOG=${TMPDIR:-/tmp}/skrift-gate-$$.log
FLAGS=(-skipPackagePluginValidation -skipMacroValidation)

(cd Skrift_Native/SkriftDesktop && xcodegen generate >/dev/null) || { echo "GATE: xcodegen (desktop) failed"; exit 1; }
if ! xcodebuild test -project Skrift_Native/SkriftDesktop/SkriftDesktop.xcodeproj -scheme UnitTests \
     -destination 'platform=macOS' "${FLAGS[@]}" >"$LOG" 2>&1; then
  grep -E "error:|failed \(" "$LOG" | head -20
  echo "GATE: RED (desktop unit suite) — log $LOG"; exit 1
fi
DESK=$(grep -E "Executed [0-9]+ tests" "$LOG" | tail -1)
echo "desktop: ${DESK:-?}"

if [[ "${1:-}" == "--full" ]]; then
  (cd Skrift_Native/SkriftMobile && xcodegen generate >/dev/null) || { echo "GATE: xcodegen (mobile) failed"; exit 1; }
  if ! xcodebuild test -project Skrift_Native/SkriftMobile/SkriftMobile.xcodeproj -scheme SkriftMobile \
       -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath Skrift_Native/SkriftMobile/build \
       "${FLAGS[@]}" -only-testing:SkriftMobileTests >"$LOG" 2>&1; then
    grep -E "error:|failed \(" "$LOG" | head -20
    echo "GATE: RED (mobile unit suite) — log $LOG"; exit 1
  fi
  MOB=$(grep -E "Executed [0-9]+ tests" "$LOG" | tail -1)
  echo "mobile: ${MOB:-?}"
fi
rm -f "$LOG"
echo "GATE: GREEN"
