#!/usr/bin/env bash
# accept.sh REPO WORKTREE ID — the only road from a worker branch into the session branch.
# Checks protected paths, merges, runs the gate (plus the item check when it is a
# backticked command), flips queue state, cleans the worktree.
# Prints at most 6 lines; everything bulky goes to .queue/.
set -euo pipefail
REPO="${1:?repo path}"; WT="${2:?worktree path}"; ID="${3:?item id}"
HERE="$(cd "$(dirname "$0")" && pwd)"
QS="$HERE/queue.sh"
cd "$REPO"
Q="QUEUE.md"
[ -f "$Q" ] || { echo "no QUEUE.md in $REPO"; exit 1; }
GATE="$(sed -n 's/^gate:[[:space:]]*//p' "$Q" | head -1)"
PROT="$(sed -n 's/^protected:[[:space:]]*//p' "$Q" | head -1)"
[ -n "$GATE" ] || { echo "no gate: line in $Q"; exit 1; }
mkdir -p .queue; printf '*\n' > .queue/.gitignore
TARGET="$(git branch --show-current)"

# a harness auto-cleans a worktree with no changes; a verify-only item ends up here.
# nothing to merge: run gate on the current branch and flip the state.
if [ ! -d "$WT" ]; then
  GLOG=".queue/$ID.gate.log"
  if bash -c "$GATE" >"$GLOG" 2>&1; then
    LANE="$("$QS" -f "$Q" get "$ID" | sed -nE 's/^### Q[0-9]+ \[(auto|tuur)\].*/\1/p' | head -1)"
    ST=done; [ "$LANE" = "tuur" ] && ST=tuur
    "$QS" -f "$Q" set "$ID" "$ST" "no changes; gate pass @$(git rev-parse --short HEAD)" >/dev/null
    echo "DONE $ID (no changes) @$(git rev-parse --short HEAD)"
    git add "$Q"; git commit -qm "queue: $ID" || true
    "$QS" -f "$Q" counts; exit 0
  else
    "$QS" -f "$Q" set "$ID" stuck "worktree gone and gate red — $GLOG" >/dev/null
    echo "GATE FAIL $ID (no worktree). tail:"; tail -3 "$GLOG"; exit 4
  fi
fi

# a harness worktree may be detached — give it a branch so we have a ref to merge
BR="$(git -C "$WT" branch --show-current)"
if [ -z "$BR" ]; then
  git -C "$WT" checkout -b "wt/$ID" >/dev/null 2>&1
  BR="wt/$ID"
fi

# workers must commit; if one forgot, commit for it (isolated tree: only its changes exist)
if ! git -C "$WT" diff --quiet || ! git -C "$WT" diff --cached --quiet; then
  git -C "$WT" add -A
  git -C "$WT" commit -qm "$ID: auto-commit at accept"
fi

# 1. protected paths untouched — unless the item carries `gate+`, which permits
# ADDITIVE growth only. An exact-test-count gate passes a gutted assertion (the count
# is unchanged), so the diff is the check, not the count.
GATEPLUS="$("$QS" -f "$Q" get "$ID" | sed -n 's/^gate+:[[:space:]]*//p' | head -1)"
if [ -n "$PROT" ] && [ "$GATEPLUS" = "yes" ]; then
  # shellcheck disable=SC2086
  ST_LIST="$(git diff --name-status "$TARGET...$BR" -- $PROT)"
  BADP="$(echo "$ST_LIST" | awk '$1 ~ /^D/ {print "deleted " $2}
                                 $1 ~ /^M/ {print "modified " $2}' )"
  # one exception: the gate script may be modified if the only lines it loses are
  # an expected-count assignment
  if [ -n "$BADP" ]; then
    GATEFILE="$(echo "$GATE" | awk '{print $1}' | sed 's|^\./||')"
    LOST="$(git diff "$TARGET...$BR" -- "$GATEFILE" 2>/dev/null | grep -E '^-[^-]' | grep -vcE '^-[[:space:]]*[A-Z_]*(EXPECTED|COUNT|TESTS)[A-Z_]*=' || true)"
    ONLYGATE="$(echo "$BADP" | grep -v "$GATEFILE" || true)"
    if [ -z "$ONLYGATE" ] && [ "${LOST:-1}" = "0" ]; then BADP=""; fi
  fi
  if [ -n "$BADP" ]; then
    "$QS" -f "$Q" set "$ID" stuck "gate weakened: $(echo "$BADP" | tr '\n' ' ')" >/dev/null
    echo "REJECT $ID — gate+ permits additions only. $(echo "$BADP" | tr '\n' ' ')"
    exit 2
  fi
elif [ -n "$PROT" ]; then
  # shellcheck disable=SC2086
  CH="$(git diff --name-only "$TARGET...$BR" -- $PROT)"
  if [ -n "$CH" ]; then
    "$QS" -f "$Q" set "$ID" stuck "touched protected: $(echo "$CH" | tr '\n' ' ')" >/dev/null
    echo "REJECT $ID — modified protected paths: $(echo "$CH" | tr '\n' ' '). Not merged."
    exit 2
  fi
fi

# 2. merge (capture the pre-merge SHA: ORIG_HEAD is stale after a no-op merge,
# and resetting to a stale ORIG_HEAD would rewind the branch)
PRE="$(git rev-parse HEAD)"
if ! git merge --no-ff --no-edit "$BR" >/dev/null 2>&1; then
  git merge --abort >/dev/null 2>&1 || true
  "$QS" -f "$Q" set "$ID" stuck "merge conflict onto $TARGET" >/dev/null
  echo "CONFLICT $ID onto $TARGET — one redispatch on a fresh base, then leave stuck."
  exit 3
fi
SHA="$(git rev-parse --short HEAD)"

undo_merge(){ # keep uncommitted queue state across the reset
  cp "$Q" .queue/queue.bak
  git reset --hard "$PRE" >/dev/null
  cp .queue/queue.bak "$Q"
}

# 3. gate
GLOG=".queue/$ID.gate.log"
if ! bash -c "$GATE" >"$GLOG" 2>&1; then
  undo_merge
  "$QS" -f "$Q" set "$ID" stuck "gate failed — $GLOG" >/dev/null
  echo "GATE FAIL $ID — merge undone. tail:"
  tail -3 "$GLOG"
  exit 4
fi

# 4. item check, only when it is a backticked command
CHECK="$("$QS" -f "$Q" get "$ID" | sed -n 's/^check:[[:space:]]*//p' | head -1)"
case "$CHECK" in
  \`*\`)
    CCMD="${CHECK#\`}"; CCMD="${CCMD%\`}"
    CLOG=".queue/$ID.check.log"
    if ! bash -c "$CCMD" >"$CLOG" 2>&1; then
      undo_merge
      "$QS" -f "$Q" set "$ID" stuck "check failed — $CLOG" >/dev/null
      echo "CHECK FAIL $ID — merge undone. tail:"
      tail -3 "$CLOG"
      exit 5
    fi
    ;;
esac

# 5. flip state (tuur-lane items park for the sitting; auto items are done)
LANE="$("$QS" -f "$Q" get "$ID" | sed -nE 's/^### Q[0-9]+ \[(auto|tuur)\].*/\1/p' | head -1)"
if [ "$LANE" = "tuur" ]; then
  "$QS" -f "$Q" set "$ID" tuur "built @$SHA — awaiting sitting" >/dev/null
  echo "PARKED $ID @$SHA (sitting)"
else
  "$QS" -f "$Q" set "$ID" done "gate pass @$SHA" >/dev/null
  echo "DONE $ID @$SHA"
fi

# commit queue state so a crash cannot orphan it (explicit path on purpose)
git add "$Q"; git commit -qm "queue: $ID" || true

# 6. clean up
git worktree remove --force "$WT" >/dev/null 2>&1 || true
git branch -D "$BR" >/dev/null 2>&1 || true
"$QS" -f "$Q" counts
