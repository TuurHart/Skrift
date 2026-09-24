#!/usr/bin/env bash
# queue.sh — sole writer of QUEUE.md state. Anyone may read the file; only this edits it.
# usage: queue.sh [-f FILE] check | table | counts | next | get ID | sitting | set ID STATE [NOTE] | add LANE TITLE...
set -euo pipefail

Q="QUEUE.md"
if [ "${1:-}" = "-f" ]; then Q="$2"; shift 2; fi
CMD="${1:-table}"; [ $# -gt 0 ] && shift || true

die(){ echo "queue.sh: $*" >&2; exit 1; }
[ -f "$Q" ] || die "no $Q here (run from project root, or pass -f)"

HDR='^### (Q[0-9]+) \[(auto|tuur)\] \(([a-z]+)\) (.*)$'

rows(){ sed -nE "s/$HDR/\1|\2|\3|\4/p" "$Q"; }

malformed(){ # any ### Q line that does not parse — warn loudly, it silently breaks next/table
  grep -nE '^### Q' "$Q" | grep -vE "^[0-9]+:${HDR#^}" || true
}

state_of(){ rows | awk -F'|' -v id="$1" '$1==id{print $3}'; }

block(){ # block ID — print that item block only
  awk -v id="$1" '
    /^### /{inb=($2==id)}
    /^## /{if($0 !~ /^###/)inb=0}
    inb' "$Q"
}

counts(){
  rows | awk -F'|' '{c[$3]++}
    END{o=""; n=split("todo doing tuur stuck done dead",S," ");
        for(i=1;i<=n;i++){s=S[i]; if(c[s]) o=o c[s] " " s " · "}
        sub(/ · $/,"",o); if(o=="") o="empty"; print "[" o "]"}'
}

case "$CMD" in
check)
  # Grammar police. Everything the skills promise about this file is asserted here,
  # so the rules cannot drift from the prose that describes them.
  P=0
  BAD="$(malformed)"
  [ -z "$BAD" ] || { echo "unparseable item lines:"; echo "$BAD"; P=1; }
  # duplicate ids
  DUP="$(rows | awk -F'|' '{print $1}' | sort | uniq -d)"
  [ -z "$DUP" ] || { echo "duplicate ids: $DUP"; P=1; }
  # every needs: resolves to a real item, and nothing needs itself
  for id in $(rows | awk -F'|' '{print $1}'); do
    for n in $(block "$id" | sed -nE 's/^needs:[[:space:]]*//p' | head -1); do
      [ "$n" = "-" ] && continue
      [ "$n" = "$id" ] && { echo "$id needs itself"; P=1; continue; }
      grep -qE "^### $n " "$Q" || { echo "$id needs $n, which is not an item"; P=1; }
    done
  done
  # a done/doing item with no evidence in the Log is a claim with nothing behind it
  for id in $(rows | awk -F'|' '$3=="done"{print $1}'); do
    grep -qE "^- .* $id -> done" "$Q" || { echo "$id is done with no Log line"; P=1; }
  done
  # an uncommitted queue is one branch-hop from silently losing state, and the
  # loss passes every grammar check, so prevention is the only defence
  if git rev-parse --git-dir >/dev/null 2>&1; then
    git diff --quiet -- "$Q" 2>/dev/null || { echo "WARN $Q has uncommitted changes — commit it with its evidence"; }
  fi
  [ "$P" = 0 ] && echo "check ok" || true
  exit $P
  ;;
table)
  rows | awk -F'|' '{printf "%-5s %-4s %-6s %s\n",$1,$2,$3,$4}'
  counts
  BAD="$(malformed)"; [ -z "$BAD" ] || { echo "WARN unparseable item lines:"; echo "$BAD"; }
  ;;
counts) counts ;;
get) block "${1:?usage: queue.sh get ID}" ;;
sitting)
  rows | awk -F'|' '$3=="tuur"{n++; printf "%d. %s %s\n",n,$1,$4} END{if(!n)print "nothing parked"}'
  ;;
next)
  # first todo item, any lane, whose needs are all done. A [tuur] item with `do: -`
  # is judgement-only: the caller parks it (set ID tuur) instead of dispatching.
  for id in $(rows | awk -F'|' '$3=="todo"{print $1}'); do
    needs="$(block "$id" | sed -nE 's/^needs:[[:space:]]*//p' | head -1)"
    ok=1
    for n in $needs; do
      [ "$n" = "-" ] && continue
      [ "$(state_of "$n")" = "done" ] || ok=0
    done
    if [ "$ok" = "1" ]; then echo "$id"; block "$id"; exit 0; fi
  done
  echo "none"
  ;;
set)
  ID="${1:?id}"; ST="${2:?state}"; NOTE="${3:-}"
  case "$ST" in todo|doing|tuur|stuck|done|dead) ;; *) die "bad state '$ST' (todo|doing|tuur|stuck|done|dead)";; esac
  grep -qE "^### $ID " "$Q" || die "no item $ID"
  perl -pi -e "s/^(### $ID \[(?:auto|tuur)\]) \([a-z]+\)/\${1} ($ST)/" "$Q"
  printf -- "- %s %s -> %s%s\n" "$(date '+%Y-%m-%d %H:%M')" "$ID" "$ST" "${NOTE:+ — $NOTE}" >> "$Q"
  echo "$ID ($ST)"
  ;;
add)
  LANE="${1:?lane auto|tuur}"; shift
  TITLE="${*:?title}"
  case "$LANE" in auto|tuur) ;; *) die "lane must be auto or tuur";; esac
  MAX="$(rows | awk -F'|' '{gsub(/Q/,"",$1); if($1+0>m)m=$1+0} END{print m+0}')"
  NID="Q$((MAX+1))"
  TMP="$Q.tmp.$$"
  awk -v blk="### $NID [$LANE] (todo) $TITLE\nspec: -\nneeds: -\ndo: (fill in)\ncheck: (fill in)\n" '
    /^## Log/ && !d {print blk; d=1}
    {print}' "$Q" > "$TMP" && mv "$TMP" "$Q"
  printf -- "- %s %s added\n" "$(date '+%Y-%m-%d %H:%M')" "$NID" >> "$Q"
  echo "$NID"
  ;;
*) die "unknown command '$CMD'" ;;
esac
