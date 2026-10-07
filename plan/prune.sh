#!/usr/bin/env bash
# prune.sh — remove this project's finished worktrees and report free disk.
# usage: plan/prune.sh [--dry]
# Removes a worktree under .claude/worktrees only when it is clean, no process has its
# cwd inside it, and its index is untouched for 3 hours (a live worker writes it).
# Branches are kept, so every committed line survives. Dirty ones are listed, never touched.
set -uo pipefail

DRY=0; [ "${1:-}" = "--dry" ] && DRY=1
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "prune.sh: not in a git repo" >&2; exit 1; }
CWDS="$(lsof -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
NOW=$(date +%s); rm_n=0; dirty=""; live=0

while read -r wt; do
  case "$wt" in */.claude/worktrees/*) ;; *) continue ;; esac
  [ -d "$wt" ] || continue
  if grep -qF "$wt" <<<"$CWDS"; then live=$((live+1)); continue; fi
  gd=$(sed -n 's/^gitdir: //p' "$wt/.git" 2>/dev/null)
  m=$(stat -f %m "$gd/index" 2>/dev/null || stat -c %Y "$gd/index" 2>/dev/null || echo 0)
  if [ $((NOW - m)) -lt 10800 ]; then live=$((live+1)); continue; fi
  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then dirty="$dirty ${wt##*/}"; continue; fi
  if [ "$DRY" = 1 ]; then rm_n=$((rm_n+1)); continue; fi
  git -C "$ROOT" worktree remove "$wt" 2>/dev/null && rm_n=$((rm_n+1))
done < <(git -C "$ROOT" worktree list --porcelain | sed -n 's/^worktree //p')

[ "$DRY" = 1 ] || git -C "$ROOT" worktree prune
FREE=$(df -g "$ROOT" 2>/dev/null | awk 'NR==2{print $4}')
echo "prune: $([ "$DRY" = 1 ] && echo would remove || echo removed) $rm_n · kept live $live · free ${FREE}G"
[ -z "$dirty" ] || echo "dirty, kept:$dirty"
[ "${FREE:-999}" -ge 50 ] || echo "WARN under 50G free — do not dispatch until this is fixed"
