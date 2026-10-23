#!/bin/bash
# lane-chain.sh <findings-file|-> <ID> [hand "<why>"] [-- next...]
# Run lane accepts strictly one after another (no pgrep waiting: waiting loops that look for
# each other's command lines deadlock). Each step appends its findings file to plan/RUN.md
# (under the accept lock), commits it, then runs plan/lane-accept.sh.
set -u
R="$(cd "$(dirname "$0")/.." && pwd)"
cd "$R"
while [ $# -gt 0 ]; do
  F=$1; ID=$2; shift 2
  MODE=auto; WHY=""
  if [ "${1:-}" = hand ]; then MODE=hand; WHY=$2; shift 2; fi
  [ "${1:-}" = "--" ] && shift
  if [ "$F" != "-" ] && [ -f "$F" ]; then
    /usr/bin/lockf -t 7200 /tmp/skrift-accept.lock bash -c "cat '$F' >> plan/RUN.md && git add plan/RUN.md && git commit -q -m 'run: $ID finding

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'"
  fi
  if [ $MODE = hand ]; then bash plan/lane-accept.sh "$ID" hand "$WHY"; else bash plan/lane-accept.sh "$ID"; fi
done
bash plan/queue.sh counts
