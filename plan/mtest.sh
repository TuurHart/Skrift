#!/bin/zsh
# plan/mtest.sh <TestClass> — run ONE phone unit-test class on the iPhone 17 sim.
# For item checks: the default gate runs the Mac suite only, so a phone-side item
# proves its own class here instead of re-running the gate. Exit 0 = green.
set -u
cd "$(dirname "$0")/.."
CLS=${1:?usage: plan/mtest.sh <TestClass>}
# -only-testing on a missing class runs 0 tests and exits 0 — refuse that.
grep -rqE "class $CLS\b" Skrift_Native/SkriftMobile/SkriftMobileTests || { echo "no test class $CLS"; exit 1; }
(cd Skrift_Native/SkriftMobile && xcodegen generate >/dev/null) || { echo "xcodegen (mobile) failed"; exit 1; }
# One sim for every worktree: SpringBoard refuses a second concurrent launch ("Busy", preflight).
# Every second run in a row hit "Application failed preflight checks / Busy" (Q79); a fresh sim
# per run clears it. Reset INSIDE the lock so no other worktree's run is on the sim.
/usr/bin/lockf -t 1800 /tmp/skrift-sim.lock bash -c 'xcrun simctl shutdown "iPhone 17" >/dev/null 2>&1; xcrun simctl erase "iPhone 17" >/dev/null 2>&1; exec "$@"' _ xcodebuild test -project Skrift_Native/SkriftMobile/SkriftMobile.xcodeproj -scheme SkriftMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath Skrift_Native/SkriftMobile/build \
  -skipPackagePluginValidation -skipMacroValidation -only-testing:"SkriftMobileTests/$CLS" -quiet
