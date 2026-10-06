#!/bin/bash
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
# Two simulators (Tuur 2026-10-06, D187): take whichever is free, else wait for the first.
# Both are iPhone 17s, so layout-sensitive tests see the same screen. Erase INSIDE the lock.
SIMS=("4962056D-2AE0-46AD-A04F-3663AE7698CF" "B7B7068C-FC3A-4A7B-B29A-EC049A86A16D")
run_on() { # run_on UDID LOCK WAIT
  /usr/bin/lockf -t "$3" "$2" bash -c 'xcrun simctl shutdown "$0" >/dev/null 2>&1; xcrun simctl erase "$0" >/dev/null 2>&1; shift; exec "$@"' "$1" \
    xcodebuild test -project Skrift_Native/SkriftMobile/SkriftMobile.xcodeproj -scheme SkriftMobile \
    -destination "platform=iOS Simulator,id=$1" -derivedDataPath Skrift_Native/SkriftMobile/build \
    -skipPackagePluginValidation -skipMacroValidation -only-testing:"SkriftMobileTests/$CLS" -quiet
}
for i in 0 1; do
  run_on "${SIMS[$i]}" "/tmp/skrift-sim$i.lock" 0; rc=$?
  [ $rc -ne 75 ] && exit $rc          # 75 = that lock was busy; try the next simulator
done
run_on "${SIMS[0]}" /tmp/skrift-sim0.lock 1800
