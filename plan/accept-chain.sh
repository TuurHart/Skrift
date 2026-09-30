#!/bin/bash
# plan/accept-chain.sh <id> <worktree-dir-name> [<id> <worktree> ...] — serial accepts.
# Waits only on REAL xcodebuild processes (by executable name, never shell command lines —
# pgrep -f on patterns deadlocked two waiters for 48 min), then runs accept.sh under one lock.
R="$(cd "$(dirname "$0")/.." && pwd)"
W="$(dirname "$R")"
busy() { ps -axo comm=,args= | awk '$1 ~ /xcodebuild$/ && /Skrift/ {f=1} END {exit !f}'; }
cd "$R"
while [ $# -gt 0 ]; do
  id=$1; wt=$2; shift 2
  n=0; while [ $n -lt 3 ]; do if busy; then n=0; else n=$((n+1)); fi; sleep 15; done
  echo "== $id"; /usr/bin/lockf -t 7200 /tmp/skrift-accept.lock bash plan/accept.sh "$R" "$W/$wt" "$id" 2>&1 | tail -6
done
