#!/bin/zsh
# plan/twin-check.sh — fails when a NEW phone/Mac twin of shared logic appears (C239).
#   ./plan/twin-check.sh              check against plan/twins.baseline (exit 1 on any new twin)
#   ./plan/twin-check.sh --baseline   rewrite plan/twins.baseline from the current tree
#   ./plan/twin-check.sh --report     print every current twin, grouped (feeds plan/twins.md)
# A twin is deliberate when its line carries `twin-ok: <reason>` — it is then skipped here.
set -u
export LC_ALL=C   # comm and sort must agree
cd "$(dirname "$0")/.."
ROOT=Skrift_Native
MOB=$ROOT/SkriftMobile; DESK=$ROOT/SkriftDesktop; SHR=$ROOT/Shared
BASE=plan/twins.baseline
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

swift_files() {  # app code only: no tests, mocks, build products
  find "$1" -name '*.swift' -not -path '*Tests*' -not -path '*/mocks/*' -not -path '*/build*' -not -path '*/.build/*' -print0
}

# 1. top-level type names (column 0 only, so nested Style/Row/Kind never count), >= 8 chars
types() {  # $1 = dir -> sorted unique names
  swift_files "$1" | xargs -0 grep -hE '^((public|private|fileprivate|internal|final|open|indirect) +)*(struct|class|enum|actor|protocol) +[A-Z][A-Za-z0-9_]{7,}' 2>/dev/null \
    | grep -v 'twin-ok' \
    | sed -E 's/^((public|private|fileprivate|internal|final|open|indirect) +)*(struct|class|enum|actor|protocol) +([A-Za-z0-9_]+).*/\4/' | sort -u
}
# 2. user-visible string literals: >= 28 chars, has a space, not a log/assert/debug line
strings() {
  swift_files "$1" | xargs -0 grep -hE '"[A-Za-z0-9][^"\\]{27,}"' 2>/dev/null \
    | grep -vE 'twin-ok|DevLog|os_log|Logger|print\(|assert|fatalError|precondition|#if DEBUG|accessibilityIdentifier|AppStorage|UserDefaults|NSLocalizedDescription' \
    | grep -oE '"[A-Za-z0-9][^"\\]{27,}"' | grep -E '"[^" ]* [^"]*"' | sort -u
}

types "$MOB"  > $T/t.mob;  types "$DESK" > $T/t.desk;  types "$SHR" > $T/t.shr
strings "$MOB" > $T/s.mob; strings "$DESK" > $T/s.desk; strings "$SHR" > $T/s.shr

{
  comm -12 $T/t.mob $T/t.desk | comm -23 - $T/t.shr | sed 's/^/type-twin\t/'        # A: same type name in both apps, not in Shared
  { comm -12 $T/t.shr $T/t.mob; comm -12 $T/t.shr $T/t.desk; } | sort -u | sed 's/^/shared-redeclared\t/'  # B: a Shared type declared again in an app
  { comm -12 $T/s.mob $T/s.desk; comm -12 $T/s.shr $T/s.mob; comm -12 $T/s.shr $T/s.desk; } | sort -u | sed 's/^/string-twin\t/'  # C: same copy typed in two trees
} | sort -u > $T/now

case "${1:-}" in
  --baseline) cp $T/now "$BASE"; echo "twin-check: baseline written, $(wc -l < $T/now | tr -d ' ') twins -> $BASE"; exit 0 ;;
  --report)   cat $T/now; exit 0 ;;
esac
[[ -f "$BASE" ]] || { echo "twin-check: no $BASE — run ./plan/twin-check.sh --baseline once"; exit 1; }
sort -u "$BASE" > $T/base
comm -13 $T/base $T/now > $T/new
if [[ -s $T/new ]]; then
  echo "TWIN-CHECK: new phone/Mac twin(s) of shared logic — move to Skrift_Native/Shared/ or mark the line 'twin-ok: <reason>':"
  sed 's/^/  /' $T/new | head -40
  exit 1
fi
echo "twin-check: ok ($(wc -l < $T/now | tr -d ' ') known, 0 new)"
