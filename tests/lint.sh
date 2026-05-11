#!/usr/bin/env bash
# DevSecOps course — local lint
#
# Fast structural checks on the course materials. Catches drift between
# README, decks, labs, and the instructor guide. Does NOT run any
# of the lab commands. Run from any dev machine.
#
# Usage:  bash tests/lint.sh
# Exit:   0 = pass, 1 = at least one check failed

set -uo pipefail

# Resolve repo root (parent of tests/)
ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$ROOT"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
PASS=0; FAIL=0
if [[ -t 1 ]]; then
  C_OK=$'\033[1;32m'; C_BAD=$'\033[1;31m'; C_DIM=$'\033[0;90m'; C_OFF=$'\033[0m'
else
  C_OK=""; C_BAD=""; C_DIM=""; C_OFF=""
fi

ok()   { echo "${C_OK}PASS${C_OFF}  $*"; PASS=$((PASS+1)); }
bad()  { echo "${C_BAD}FAIL${C_OFF}  $*"; FAIL=$((FAIL+1)); }
note() { echo "${C_DIM}---${C_OFF}   $*"; }

section() { echo; echo "== $* =="; }

# ---------------------------------------------------------------------------
# Section 1: required top-level files
# ---------------------------------------------------------------------------
section "Top-level files"

for f in README.md INSTRUCTOR.md DevSecOps-Outline.pdf; do
  [[ -f "$f" ]] && ok "$f exists" || bad "$f missing"
done

[[ -d presentations ]] && ok "presentations/ exists" || bad "presentations/ missing"
[[ -d labs          ]] && ok "labs/ exists"          || bad "labs/ missing"

# ---------------------------------------------------------------------------
# Section 2: presentations
# ---------------------------------------------------------------------------
section "Presentations (9 module decks)"

EXPECTED_DECKS=(
  module-01-what-is-devsecops.html
  module-02-thinking-like-a-hacker.html
  module-03-app-vs-infra-threats.html
  module-04-threat-maps.html
  module-05-owasp-upstream.html
  module-06-pen-testing-fundamentals.html
  module-07-pen-testing-tools.html
  module-08-azure-monitoring.html
  module-09-automation-jenkins.html
)

for deck in "${EXPECTED_DECKS[@]}"; do
  path="presentations/$deck"
  if [[ ! -f "$path" ]]; then
    bad "$deck missing"
    continue
  fi

  # Required structural elements
  errs=()
  grep -q "<title>" "$path"            || errs+=("no <title>")
  grep -q "Reveal.initialize"  "$path" || errs+=("no Reveal.initialize call")
  grep -q "reveal.js@4"        "$path" || errs+=("not pinned to reveal.js v4")
  grep -q '<aside class="notes"' "$path" || errs+=("no instructor notes")
  grep -q "lab-callout\|questions-slide\|module-progress" "$path" \
                                       || errs+=("missing standard slide classes")

  if (( ${#errs[@]} == 0 )); then
    ok "$deck structure"
  else
    bad "$deck — ${errs[*]}"
  fi
done

# Density check: no code block > 14 lines (would overflow on a slide)
section "Slide density"
overflow=0
for path in presentations/module-*.html; do
  count=$(awk '/<pre><code/{f=1; n=0} f{n++} /<\/code><\/pre>/{f=0; if(n>14) print FILENAME":"n}' "$path")
  if [[ -n "$count" ]]; then
    bad "$(basename "$path") — code block(s) >14 lines: $count"
    overflow=$((overflow+1))
  fi
done
(( overflow == 0 )) && ok "no overflowing code blocks across all decks"

# ---------------------------------------------------------------------------
# Section 3: labs
# ---------------------------------------------------------------------------
section "Labs"

for dir in labs/lab-*; do
  name=$(basename "$dir")
  if [[ ! -f "$dir/README.md" ]]; then
    bad "$dir/README.md missing"
    continue
  fi

  errs=()
  grep -qE "^# (Lab|Module)"            "$dir/README.md" || errs+=("no top-level title")
  grep -q "^## Lab overview\|^## Format" "$dir/README.md" || errs+=("no Lab overview section")
  grep -q "Objectives"                  "$dir/README.md" || errs+=("no Objectives")
  grep -qE "^>\s*(⏱|⏰)|Duration"       "$dir/README.md" || errs+=("no Duration line")

  # Troubleshooting only required for labs with shell commands
  if grep -q '```bash' "$dir/README.md"; then
    grep -q "Troubleshooting\|## Common\|Cleanup\|cleanup" "$dir/README.md" \
      || errs+=("no Troubleshooting/Cleanup section (lab has shell commands)")
  fi

  if (( ${#errs[@]} == 0 )); then
    ok "$name/README.md structure"
  else
    bad "$name/README.md — ${errs[*]}"
  fi
done

# Lab-1 setup script must exist & be executable
[[ -x labs/lab-01/scripts/setup-cloud9.sh ]] && ok "lab-01/scripts/setup-cloud9.sh executable" \
                                              || bad "lab-01/scripts/setup-cloud9.sh missing or not +x"

# Lab-8 send-events script must exist & be executable
[[ -x labs/lab-08/scripts/send-events.sh ]] && ok "lab-08/scripts/send-events.sh executable" \
                                              || bad "lab-08/scripts/send-events.sh missing or not +x"

# ---------------------------------------------------------------------------
# Section 4: cross-document consistency
# ---------------------------------------------------------------------------
section "Cross-document consistency"

# README schedule must reference all 9 modules
missing=()
for n in 1 2 3 4 5 6 7 8 9; do
  grep -qE "Module ${n}\b|\\*\\*Module $n\\*\\*" README.md || missing+=("Module $n")
done
if (( ${#missing[@]} == 0 )); then
  ok "README schedule references Modules 1-9"
else
  bad "README schedule missing: ${missing[*]}"
fi

# README must reference all 9 labs
missing=()
for n in 1 2 3 4 5 6 7 8 9; do
  grep -qE "Lab ${n}\b" README.md || missing+=("Lab $n")
done
if (( ${#missing[@]} == 0 )); then
  ok "README references Labs 1-9"
else
  bad "README missing lab references: ${missing[*]}"
fi

# Cloud9 environment naming consistency: <your-name> placeholder used everywhere
inconsistent=$(grep -lE "devsecops-lab-(student|user1|test)\b" labs/*/README.md 2>/dev/null || true)
[[ -z "$inconsistent" ]] && ok "no hard-coded student names in lab READMEs" \
                          || bad "hard-coded student names: $inconsistent"

# AWS resource namespacing — every `aws ... create-*/put-*` command in Lab 8 must
# either reference a variable that itself contains $YOU/$\{YOU\}, or be flagged.
# Approach: check that the variables used in those commands ($LG, $ALARM, $TOPIC,
# $TOPIC_ARN, $LS) are themselves derived from $YOU.
lab8="labs/lab-08/README.md"
defs=$(grep -E '^(LG|LS|TOPIC|ALARM)=' "$lab8" || true)
unscoped_def=0
while IFS= read -r line; do
  var=${line%%=*}
  [[ "$var" == "LS" ]] && continue   # LS is a child of LG namespace, OK
  if ! grep -qE "^${var}=.*(\\\$YOU|\\\$\\{YOU\\})" "$lab8"; then
    unscoped_def=1
    bad "Lab 8 var \$$var not derived from \$YOU: $line"
  fi
done <<< "$defs"
(( unscoped_def == 0 )) && ok "Lab 8 AWS resources name-scoped by \$YOU (via \$LG, \$TOPIC, \$ALARM)"

# Schedule arithmetic: Day 1 + Day 2 should sum to ~660 net minutes
# Strategy: for each schedule table, sum the numbers in parentheses.
# Each Day section is "### Day N — ..." followed by a table; we collect all
# `(NN)` markers between the schedule tables and the next H3.
total_min=$(awk '
  /^### Day [12]/ { capturing=1; next }
  capturing && /^### / { capturing=0 }
  capturing { print }
' README.md | grep -oE '\([0-9]+' | tr -d '(' | paste -sd+ - | bc 2>/dev/null)
total_min=${total_min:-0}
if [[ "$total_min" -ge 600 && "$total_min" -le 720 ]]; then
  ok "Schedule sums to $total_min min (target ~660)"
else
  bad "Schedule sums to $total_min min — expected 600-720"
fi

# ---------------------------------------------------------------------------
# Section 5: INSTRUCTOR.md must reference key items
# ---------------------------------------------------------------------------
section "Instructor guide"

inst_errs=()
grep -q "Pre-class checklist\|pre-class"     INSTRUCTOR.md || inst_errs+=("no pre-class checklist")
grep -q "Lab 4\|Juice Shop"                   INSTRUCTOR.md || inst_errs+=("no Lab 4 solutions")
grep -q "Lab 9\|capstone"                     INSTRUCTOR.md || inst_errs+=("no Lab 9 verification")
grep -q "devsecops-lab-role"                  INSTRUCTOR.md || inst_errs+=("no IAM role mention")

if (( ${#inst_errs[@]} == 0 )); then
  ok "INSTRUCTOR.md covers required topics"
else
  bad "INSTRUCTOR.md gaps: ${inst_errs[*]}"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "================================================"
echo "  Results: ${C_OK}${PASS} passed${C_OFF}, ${C_BAD}${FAIL} failed${C_OFF}"
echo "================================================"
exit $(( FAIL == 0 ? 0 : 1 ))
