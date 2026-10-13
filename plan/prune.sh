#!/usr/bin/env bash
# prune.sh — remove this project's finished worktrees and report free disk.
# usage: plan/prune.sh [--dry]
# A worktree under .claude/worktrees is left alone while a process has its cwd inside it
# or anything in it (a commit, an edited file) is under 72 hours old. Past that:
#   clean  → removed.
#   dirty  → its uncommitted work is committed to its own branch (rescue/<name> if
#            detached) first, then removed. Build output stays out of that commit:
#            any path with a build/DerivedData/.build segment, and untracked files over 1MB.
# Branches are never deleted, so nothing committed or rescued is lost.
set -uo pipefail

DRY=0; [ "${1:-}" = "--dry" ] && DRY=1
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "prune.sh: not in a git repo" >&2; exit 1; }
CWDS="$(lsof -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
NOW=$(date +%s); AGE=$((72*3600)); rm_n=0; rescued=0; live=0
JUNK='(^|/)(build[^/]*|DerivedData|\.build)(/|$)'

mtime(){ stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

while read -r wt; do
  case "$wt" in */.claude/worktrees/*) ;; *) continue ;; esac
  [ -d "$wt" ] || continue
  if grep -qF "$wt" <<<"$CWDS"; then live=$((live+1)); continue; fi
  last=$(git -C "$wt" log -1 --format=%ct 2>/dev/null || echo 0)
  changed="$(git -C "$wt" status --porcelain 2>/dev/null)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    m=$(mtime "$wt/$f"); [ "$m" -gt "$last" ] && last=$m
  done < <(cut -c4- <<<"$changed" | grep -vE "$JUNK" | head -200)
  if [ $((NOW - last)) -lt $AGE ]; then live=$((live+1)); continue; fi

  if [ -n "$changed" ]; then
    if [ "$DRY" = 1 ]; then rescued=$((rescued+1)); rm_n=$((rm_n+1)); continue; fi
    git -C "$wt" symbolic-ref -q HEAD >/dev/null || git -C "$wt" switch -q -c "rescue/${wt##*/}"
    git -C "$wt" add -u -- . 2>/dev/null
    git -C "$wt" status --porcelain | sed -n 's/^?? //p' | grep -vE "$JUNK" | while IFS= read -r f; do
      [ "$(du -sk "$wt/$f" | cut -f1)" -le 1024 ] && git -C "$wt" add -- "$f"
    done
    git -C "$wt" diff --cached --name-only | grep -E "$JUNK" | while IFS= read -r f; do git -C "$wt" reset -q -- "$f"; done
    if ! git -C "$wt" diff --cached --quiet; then
      git -C "$wt" commit -q --no-verify -m "rescue: uncommitted work from worktree ${wt##*/}, saved by prune.sh before removal" || { echo "rescue failed, kept: ${wt##*/}"; continue; }
      rescued=$((rescued+1))
    fi
    git -C "$ROOT" worktree remove --force "$wt" 2>/dev/null && rm_n=$((rm_n+1))
  else
    [ "$DRY" = 1 ] && { rm_n=$((rm_n+1)); continue; }
    git -C "$ROOT" worktree remove "$wt" 2>/dev/null && rm_n=$((rm_n+1))
  fi
done < <(git -C "$ROOT" worktree list --porcelain | sed -n 's/^worktree //p')

[ "$DRY" = 1 ] || git -C "$ROOT" worktree prune
FREE=$(df -g "$ROOT" 2>/dev/null | awk 'NR==2{print $4}')
echo "prune: $([ "$DRY" = 1 ] && echo would remove || echo removed) $rm_n ($rescued with work rescued to their branch) · kept live $live · free ${FREE}G"
[ "${FREE:-999}" -ge 50 ] || echo "WARN under 50G free — do not dispatch until this is fixed"
