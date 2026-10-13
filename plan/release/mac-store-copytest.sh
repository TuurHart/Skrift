#!/bin/bash
# Q367: Mac store copy-test. FOR TUUR TO RUN; agents never run it without --self-test.
#
#   plan/release/mac-store-copytest.sh              copy the PROD Mac stores to a fresh temp dir,
#                                                   open the copy with this checkout's models,
#                                                   print counts before/after, delete the copy
#   plan/release/mac-store-copytest.sh --self-test  the same path on a synthetic store built from
#                                                   test-fixtures/corpus (never reads real data),
#                                                   plus the merge dry run on a synthetic pair
#   plan/release/mac-store-copytest.sh --merge <old store dir>
#                                                   Q399 (ICLOUD_MERGE step 8): copy the moved
#                                                   Dev-era memo_cloud.store and the live
#                                                   Production one (app quit) to a fresh temp dir,
#                                                   run DevEraMerge on the copies, print counts and
#                                                   checks, delete the copies
#
# Prints counts only: notes, assets, enhancements, people, name decisions, unlinked names. Never a
# title, a name or any text. CloudKit is never touched (both stores open with cloudKitDatabase
# .none). Exit 0 = no count dropped; 1 = a drop (or self-test failure); 2 = error; 3 = refused.
#
# Prod stores (AppPaths, Release): ~/Library/Application Support/Skrift/skrift.store (local
# PipelineFile store) and memo_cloud.store (the CloudKit mirror), each with -wal/-shm and an
# optional .<name>_SUPPORT folder (Core Data external data).
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DESKTOP="$ROOT/Skrift_Native/SkriftDesktop"
DERIVED="$DESKTOP/build-copytest"
TOOL="$DERIVED/Build/Products/Debug/StoreCopyTest"
REAL="$HOME/Library/Application Support/Skrift"
STORES="skrift.store memo_cloud.store"

say() { printf '%s\n' "$*"; }
die() { say "mac-store-copytest: $*" >&2; exit 2; }

build_tool() {
    say "building StoreCopyTest (Debug, MLX-free)..."
    (cd "$DESKTOP" && xcodegen generate >/dev/null) || die "xcodegen failed"
    (cd "$DESKTOP" && xcodebuild build -scheme StoreCopyTest -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED" -quiet >"$DERIVED.log" 2>&1)
    local rc=$?
    [ -x "$TOOL" ] || die "build failed (exit $rc), see $DERIVED.log"
}

# copy_stores <source dir> <dest dir> [store names]: each store + -wal/-shm + .<stem>_SUPPORT,
# then the marker. Default store names: $STORES.
copy_stores() {
    local src="$1" dst="$2" names="${3:-$STORES}" n=0 s stem
    mkdir -p "$dst" && chmod 700 "$dst"
    for s in $names; do
        for f in "$s" "$s-wal" "$s-shm"; do
            if [ -f "$src/$f" ]; then cp -p "$src/$f" "$dst/$f" || die "copy failed: $f"; n=$((n + 1)); fi
        done
        stem="${s%.store}"
        if [ -d "$src/.${stem}_SUPPORT" ]; then
            cp -Rp "$src/.${stem}_SUPPORT" "$dst/.${stem}_SUPPORT" || die "copy failed: .${stem}_SUPPORT"
            n=$((n + 1))
        fi
    done
    touch "$dst/.skrift-copytest"
    say "copied $n store files to a fresh temp dir"
}

# run_tool <copy dir> [extra args]: --cloud only when the copy has memo_cloud.store.
run_tool() {
    local dir="$1"; shift
    if [ -f "$dir/memo_cloud.store" ]; then
        "$TOOL" --local "$dir/skrift.store" --cloud "$dir/memo_cloud.store" "$@"
    else
        say "(no memo_cloud.store: synced counts skipped)"
        "$TOOL" --local "$dir/skrift.store" "$@"
    fi
}

self_test() {
    build_tool
    local work fail=0 rc
    work="$(mktemp -d "${TMPDIR:-/tmp}/skrift-copytest-self.XXXXXX")" || die "mktemp failed"
    trap 'rm -rf "$work"' EXIT
    local src="$work/fake-app-support"
    # The synthetic source plays the real folder: the tool must refuse it like the real one.
    export SKRIFT_COPYTEST_PROTECTED="$src"

    say "== build a synthetic store from test-fixtures/corpus"
    SKRIFT_COPYTEST_PROTECTED="" "$TOOL" --make-synthetic "$src" --corpus "$ROOT/test-fixtures/corpus" || die "synthetic build failed"

    say "== 1. the tool refuses the source (stand-in for the real store)"
    touch "$src/.skrift-copytest"   # even with a marker, the protected folder is refused
    "$TOOL" --local "$src/skrift.store" --cloud "$src/memo_cloud.store" >/dev/null 2>&1; rc=$?
    if [ "$rc" = 3 ]; then say "refused (exit 3): ok"; else say "FAIL: expected exit 3, got $rc"; fail=1; fi
    rm -f "$src/.skrift-copytest"
    # (The real folder is guarded by the same loop; the self-test never names a real path.)

    say "== 2. the copy path: no drop, every count non-zero"
    copy_stores "$src" "$work/copy"
    run_tool "$work/copy" --require-nonzero; rc=$?
    if [ "$rc" = 0 ]; then say "copy test exit 0: ok"; else say "FAIL: copy test exit $rc"; fail=1; fi

    say "== 3. a dropped note fails the run"
    copy_stores "$src" "$work/copy-drop"
    run_tool "$work/copy-drop" --simulate-drop >/dev/null; rc=$?
    if [ "$rc" = 1 ]; then say "simulated drop exit 1: ok"; else say "FAIL: simulated drop exit $rc"; fail=1; fi

    merge_self_test "$work" || fail=1

    if [ "$fail" = 0 ]; then say "self-test: PASS"; exit 0; fi
    say "self-test: FAIL"; exit 1
}

# expect_line <output file> <exact line>
expect_line() {
    if grep -qxF "$2" "$1"; then say "  \"$2\": ok"; return 0; fi
    say "  FAIL: missing line \"$2\""; return 1
}

# Q399: the merge dry run on a synthetic OLD + PROD pair. Returns non-zero on any failure.
merge_self_test() {
    local work="$1" fail=0 rc out="$1/merge-out.txt"
    local msrc="$work/fake-merge-source"
    local mac="--mac-device-id synthetic-mac"
    export SKRIFT_COPYTEST_PROTECTED="$msrc/old:$msrc/prod"

    say "== merge 0. build a synthetic OLD + PROD pair"
    SKRIFT_COPYTEST_PROTECTED="" "$TOOL" --make-merge-synthetic "$msrc" || { say "FAIL: synthetic merge pair"; return 1; }

    say "== merge 1. the tool refuses the source pair (stand-in for the real stores)"
    touch "$msrc/old/.skrift-copytest" "$msrc/prod/.skrift-copytest"
    "$TOOL" --merge-dry-run --old "$msrc/old/memo_cloud.store" --prod "$msrc/prod/memo_cloud.store" $mac >/dev/null 2>&1; rc=$?
    if [ "$rc" = 3 ]; then say "refused (exit 3): ok"; else say "FAIL: expected exit 3, got $rc"; fail=1; fi
    rm -f "$msrc/old/.skrift-copytest" "$msrc/prod/.skrift-copytest"

    say "== merge 2. a copy without the marker is refused"
    mkdir -p "$work/nomarker" && cp -p "$msrc/old/memo_cloud.store" "$work/nomarker/memo_cloud.store"
    "$TOOL" --merge-dry-run --old "$work/nomarker/memo_cloud.store" --prod "$work/nomarker/memo_cloud.store" $mac >/dev/null 2>&1; rc=$?
    if [ "$rc" = 3 ]; then say "no marker refused (exit 3): ok"; else say "FAIL: expected exit 3, got $rc"; fail=1; fi

    say "== merge 3. the dry run on copies: every check passes, counts as built"
    copy_stores "$msrc/old" "$work/m/old" "memo_cloud.store"
    copy_stores "$msrc/prod" "$work/m/prod" "memo_cloud.store"
    "$TOOL" --merge-dry-run --old "$work/m/old/memo_cloud.store" --prod "$work/m/prod/memo_cloud.store" $mac >"$out" 2>&1; rc=$?
    cat "$out"
    if [ "$rc" = 0 ]; then say "merge dry run exit 0: ok"; else say "FAIL: merge dry run exit $rc"; fail=1; fi
    for want in "OLD only, Mac-made: 2" "OLD only, phone after S: 1" "OLD only, trashed (skipped): 1" \
                "OLD only, phone before S (skipped, limit 20): 2" "PROD only: 5" "ids in both: 10" \
                "PROD duplicate id groups: 1" "notes to insert: 3" "assets to insert: 5" \
                "enhancements OLD only (insert): 2" "enhancements OLD newer (OLD wins): 1" \
                "enhancements PROD newer (PROD kept): 1" "enhancements tie (PROD kept): 1" \
                "fields copied, title: 1" "fields copied, trash: 1" \
                "conflicts (edited on both sides after S, PROD kept): 1" "diverged (no stamp, PROD kept): 2" \
                "notes inserted: 3" "PROD after duplicate id groups: 1"; do
        expect_line "$out" "$want" || fail=1
    done
    if grep -q "SYNTHETIC-PRIVATE" "$out"; then say "FAIL: note text reached the output"; fail=1
    else say "no note text in the output: ok"; fi
    if grep -qE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' "$out"; then
        say "FAIL: a note id reached the output"; fail=1
    else say "no note id in the output: ok"; fi

    say "== merge 4. a dropped PROD note fails the run"
    copy_stores "$msrc/old" "$work/md/old" "memo_cloud.store"
    copy_stores "$msrc/prod" "$work/md/prod" "memo_cloud.store"
    "$TOOL" --merge-dry-run --old "$work/md/old/memo_cloud.store" --prod "$work/md/prod/memo_cloud.store" $mac --simulate-drop >/dev/null 2>&1; rc=$?
    if [ "$rc" = 1 ]; then say "simulated drop exit 1: ok"; else say "FAIL: simulated drop exit $rc"; fail=1; fi

    say "== merge 5. more than 20 old-only phone notes before S stops the plan"
    local bsrc="$work/fake-merge-blocked"
    export SKRIFT_COPYTEST_PROTECTED="$msrc/old:$msrc/prod:$bsrc/old:$bsrc/prod"
    SKRIFT_COPYTEST_PROTECTED="" "$TOOL" --make-merge-synthetic "$bsrc" --phone-before-split 21 >/dev/null || { say "FAIL: blocked pair"; return 1; }
    copy_stores "$bsrc/old" "$work/mb/old" "memo_cloud.store"
    copy_stores "$bsrc/prod" "$work/mb/prod" "memo_cloud.store"
    "$TOOL" --merge-dry-run --old "$work/mb/old/memo_cloud.store" --prod "$work/mb/prod/memo_cloud.store" $mac >"$out" 2>&1; rc=$?
    if [ "$rc" = 1 ] && grep -q "^RESULT: STOP" "$out"; then say "stop (exit 1): ok"; else say "FAIL: expected STOP exit 1, got $rc"; fail=1; fi

    if [ "$fail" = 0 ]; then say "merge self-test: PASS"; return 0; fi
    say "merge self-test: FAIL"; return 1
}

# Q399 (ICLOUD_MERGE step 8): the merge dry run on copies of the moved Dev-era store and the
# downloaded Production store. FOR TUUR TO RUN, with Skrift quit.
merge_run() {
    local olddir="${1:-}" work rc macid
    [ -n "$olddir" ] || die "usage: $0 --merge <old store dir, e.g. ~/Library/Application Support/Skrift/merge-from-dev>"
    [ -f "$olddir/memo_cloud.store" ] || die "no memo_cloud.store in $olddir"
    [ -f "$REAL/memo_cloud.store" ] || die "no Production store at ~/Library/Application Support/Skrift/memo_cloud.store"
    if pgrep -x Skrift >/dev/null; then die "quit Skrift first: copying a store the app is writing gives a torn copy"; fi
    # The Mac's own DeviceID (DeviceID.defaultsKey in the Release app's defaults): marks Mac-made notes.
    macid="$(defaults read com.skrift.desktop skriftDeviceID 2>/dev/null)"
    [ -n "$macid" ] || die "could not read the Mac's DeviceID (defaults read com.skrift.desktop skriftDeviceID)"
    build_tool   # before the copy, so a build failure leaves no copy of real data behind
    work="$(mktemp -d "${TMPDIR:-/tmp}/skrift-merge-dryrun.XXXXXX")" || die "mktemp failed"
    trap 'rm -rf "$work"' EXIT
    if pgrep -x Skrift >/dev/null; then die "Skrift started during the build; quit it and re-run"; fi
    copy_stores "$olddir" "$work/old" "memo_cloud.store"
    copy_stores "$REAL" "$work/prod" "memo_cloud.store"
    "$TOOL" --merge-dry-run --old "$work/old/memo_cloud.store" --prod "$work/prod/memo_cloud.store" \
        --mac-device-id "$macid"; rc=$?
    say "(temp copies deleted)"
    exit "$rc"
}

real_run() {
    [ -f "$REAL/skrift.store" ] || die "no prod store at ~/Library/Application Support/Skrift/skrift.store"
    if pgrep -x Skrift >/dev/null; then die "quit Skrift first: copying a store the app is writing gives a torn copy"; fi
    build_tool   # before the copy, so a build failure leaves no copy of real data behind
    local work rc
    work="$(mktemp -d "${TMPDIR:-/tmp}/skrift-copytest.XXXXXX")" || die "mktemp failed"
    trap 'rm -rf "$work"' EXIT
    if pgrep -x Skrift >/dev/null; then die "Skrift started during the build; quit it and re-run"; fi
    copy_stores "$REAL" "$work/copy"
    run_tool "$work/copy"; rc=$?
    say "(temp copy deleted)"
    exit "$rc"
}

case "${1:-}" in
    --self-test) self_test ;;
    --merge) merge_run "${2:-}" ;;
    "") real_run ;;
    *) die "usage: $0 [--self-test | --merge <old store dir>]" ;;
esac
