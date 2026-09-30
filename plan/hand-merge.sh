#!/bin/bash
# plan/hand-merge.sh <id> <worktree-dir-name> "<decision>" — merge a worker branch whose protected-test
# changes Tuur approved (accept.sh rejects any protected change). Same gate + item check as accept.sh;
# on any red the merge is undone. Prints only tails. Run it under the accept lock:
#   /usr/bin/lockf -t 7200 /tmp/skrift-accept.lock bash plan/hand-merge.sh <id> <wt> "<why>"
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"; W="$(dirname "$R")"; ID=$1; WT="$W/$2"; WHY=$3
cd "$R"
busy() { ps -axo comm=,args= | awk '$1 ~ /xcodebuild$/ && /Skrift/ {f=1} END {exit !f}'; }
n=0; while [ $n -lt 3 ]; do if busy; then n=0; else n=$((n+1)); fi; sleep 15; done
BR="$(git -C "$WT" branch --show-current)"
PRE="$(git rev-parse HEAD)"
git merge --no-ff "$BR" -m "Merge $BR into $(git branch --show-current) — hand-merged, protected changes approved ($WHY)" >/dev/null 2>&1 || { git merge --abort 2>/dev/null; echo "CONFLICT $ID"; exit 3; }
CHECK="$(bash plan/queue.sh get "$ID" | sed -n 's/^check:[[:space:]]*`\(.*\)`[[:space:]]*$/\1/p')"
if ./gate.sh > ".queue/$ID.gate.log" 2>&1 && bash -c "$CHECK" > ".queue/$ID.check.log" 2>&1; then
  bash plan/queue.sh set "$ID" done "hand-merged ($WHY)" | tail -1
  git add QUEUE.md && git commit -qm "queue: $ID" ; echo "DONE $ID @$(git rev-parse --short HEAD~1)"; bash plan/queue.sh table | tail -1
else
  git reset -q --hard "$PRE"; echo "FAIL $ID — merge undone"; tail -3 ".queue/$ID.gate.log" ".queue/$ID.check.log" 2>/dev/null | tail -6
fi
