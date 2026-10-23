#!/bin/bash
# lane-accept.sh <ID> [hand "<why>"] — accept a lane chat's wt/<ID> branch from a throwaway
# worktree so the lane's own worktree and branch survive accept.sh's cleanup.
set -u
R=/Users/tiurihartog/Hackerman/Skrift/.claude/worktrees/skrift-parity-audit-91f702
W=/Users/tiurihartog/Hackerman/Skrift/.claude/worktrees
ID=$1; MODE=${2:-auto}; WHY=${3:-}
cd "$R"
git worktree remove --force "$W/acc-$ID" >/dev/null 2>&1; git branch -D "acc/$ID" >/dev/null 2>&1
git branch -f "acc/$ID" "wt/$ID" >/dev/null && git worktree add -q "$W/acc-$ID" "acc/$ID" || { echo "no branch wt/$ID"; exit 1; }
# Shared Mac with other projects: wait until the 1-minute load average is under 40 (Onderons rule, 2026-10-23).
while [ "$(sysctl -n vm.loadavg | awk '{print int($2)}')" -ge 40 ]; do sleep 60; done
if [ "$MODE" = hand ]; then
  /usr/bin/lockf -t 7200 /tmp/skrift-accept.lock bash plan/hand-merge.sh "$ID" "acc-$ID" "$WHY" 2>&1 | tail -4
else
  /usr/bin/lockf -t 7200 /tmp/skrift-accept.lock bash plan/accept.sh "$R" "$W/acc-$ID" "$ID" 2>&1 | tail -4
fi
git worktree remove --force "$W/acc-$ID" >/dev/null 2>&1; git branch -D "acc/$ID" >/dev/null 2>&1; true
