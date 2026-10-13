#!/bin/bash
# Q367: Mac store copy-test. FOR TUUR TO RUN; agents never run it without --self-test.
#
#   plan/release/mac-store-copytest.sh              copy the PROD Mac stores to a fresh temp dir,
#                                                   open the copy with this checkout's models,
#                                                   print counts before/after, delete the copy
#   plan/release/mac-store-copytest.sh --self-test  the same path on a synthetic store built from
#                                                   test-fixtures/corpus (never reads real data)
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

# copy_stores <source dir> <dest dir>: each store + -wal/-shm + .<stem>_SUPPORT, then the marker.
copy_stores() {
    local src="$1" dst="$2" n=0 s stem
    mkdir -p "$dst" && chmod 700 "$dst"
    for s in $STORES; do
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

    if [ "$fail" = 0 ]; then say "self-test: PASS"; exit 0; fi
    say "self-test: FAIL"; exit 1
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
    "") real_run ;;
    *) die "usage: $0 [--self-test]" ;;
esac
