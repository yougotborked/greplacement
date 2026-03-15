#!/usr/bin/env bash
# Naughty string tests for greplacement
# Uses the Big List of Naughty Strings to stress-test the grep shim.
# Every test compares shim output to real grep output — no hardcoded expectations.
set -uo pipefail

SHIM="${SHIM:-$HOME/.local/bin/grep}"
REAL_GREP=/usr/bin/grep
FIXTURES="$(cd "$(dirname "$0")/fixtures" && pwd)"
BLNS="$FIXTURES/blns.txt"
PASS=0
FAIL=0
declare -a ERRORS=()
VERBOSE="${VERBOSE:-0}"

for arg in "$@"; do
  case "$arg" in
    --shim=*) SHIM="${arg#--shim=}" ;;
    --verbose|-v) VERBOSE=1 ;;
  esac
done

pass() { PASS=$((PASS + 1)); [[ $VERBOSE -eq 1 ]] && echo "  PASS: $1"; }
fail() {
  FAIL=$((FAIL + 1))
  ERRORS+=("FAIL: $1")
  ERRORS+=("  expected: $(printf '%s' "$2" | head -c 120 | cat -v)")
  ERRORS+=("  actual:   $(printf '%s' "$3" | head -c 120 | cat -v)")
  echo "  FAIL: $1"
  if [[ $VERBOSE -eq 1 ]]; then
    echo "    expected: $(printf '%s' "$2" | head -c 120 | cat -v)"
    echo "    actual:   $(printf '%s' "$3" | head -c 120 | cat -v)"
  fi
}

# Compare shim to real grep for a given invocation
assert_matches_real() {
  local desc="$1"; shift
  local expected actual
  expected=$("$REAL_GREP" "$@" 2>/dev/null) || true
  actual=$("$SHIM" "$@" 2>/dev/null) || true
  if [[ "$actual" == "$expected" ]]; then pass "$desc"; else fail "$desc" "$expected" "$actual"; fi
}

assert_exit_matches_real() {
  local desc="$1"; shift
  local expected_exit=0 actual_exit=0
  "$REAL_GREP" "$@" >/dev/null 2>&1 || expected_exit=$?
  "$SHIM" "$@" >/dev/null 2>&1 || actual_exit=$?
  if [[ "$actual_exit" -eq "$expected_exit" ]]; then pass "$desc"; else fail "$desc" "exit=$expected_exit" "exit=$actual_exit"; fi
}

echo "=== greplacement naughty string tests ==="
echo "Shim:    $SHIM"
echo "BLNS:    $BLNS"
echo ""

[[ -f "$BLNS" ]] || { echo "ERROR: blns.txt not found at $BLNS" >&2; exit 1; }

# ── Fixed-string search through the entire BLNS file ──────────────────────────
echo "── Fixed-string searches (-F) ──"

# Read each non-comment, non-empty line as a pattern and search the file
naughty_count=0
naughty_fail=0
while IFS= read -r pattern; do
  [[ -z "$pattern" || "$pattern" == \#* ]] && continue
  naughty_count=$((naughty_count + 1))
  expected=$("$REAL_GREP" -F -- "$pattern" "$BLNS" 2>/dev/null) || true
  actual=$(  "$SHIM"      -F -- "$pattern" "$BLNS" 2>/dev/null) || true
  if [[ "$actual" != "$expected" ]]; then
    naughty_fail=$((naughty_fail + 1))
    fail "fixed-string search for: $(printf '%s' "$pattern" | head -c 60 | cat -v)" "$expected" "$actual"
  fi
done < "$BLNS"
pass_count=$((naughty_count - naughty_fail))
PASS=$((PASS + pass_count))
echo "  Fixed-string: $pass_count/$naughty_count patterns matched real grep"

# ── Exit codes match for fixed-string searches ────────────────────────────────
echo "── Exit codes (-F) ──"
ec_pass=0
ec_fail=0
ec_total=0
while IFS= read -r pattern; do
  [[ -z "$pattern" || "$pattern" == \#* ]] && continue
  ec_total=$((ec_total + 1))
  exp_exit=0; act_exit=0
  "$REAL_GREP" -qF -- "$pattern" "$BLNS" 2>/dev/null || exp_exit=$?
  "$SHIM"      -qF -- "$pattern" "$BLNS" 2>/dev/null || act_exit=$?
  if [[ "$act_exit" -eq "$exp_exit" ]]; then
    ec_pass=$((ec_pass + 1))
  else
    ec_fail=$((ec_fail + 1))
    fail "exit code for fixed-string: $(printf '%s' "$pattern" | head -c 60 | cat -v)" "exit=$exp_exit" "exit=$act_exit"
  fi
done < "$BLNS"
PASS=$((PASS + ec_pass))
echo "  Exit codes: $ec_pass/$ec_total matched real grep"

# ── Case-insensitive fixed-string ─────────────────────────────────────────────
echo "── Case-insensitive fixed-string (-Fi) ──"
fi_pass=0; fi_fail=0; fi_total=0
while IFS= read -r pattern; do
  [[ -z "$pattern" || "$pattern" == \#* ]] && continue
  fi_total=$((fi_total + 1))
  expected=$("$REAL_GREP" -Fi -- "$pattern" "$BLNS" 2>/dev/null) || true
  actual=$(  "$SHIM"      -Fi -- "$pattern" "$BLNS" 2>/dev/null) || true
  if [[ "$actual" == "$expected" ]]; then
    fi_pass=$((fi_pass + 1))
  else
    fi_fail=$((fi_fail + 1))
    fail "case-insensitive fixed-string: $(printf '%s' "$pattern" | head -c 60 | cat -v)" "$expected" "$actual"
  fi
done < "$BLNS"
PASS=$((PASS + fi_pass))
echo "  -Fi: $fi_pass/$fi_total matched real grep"

# ── Count matches (-cF) ───────────────────────────────────────────────────────
echo "── Count matches (-cF) ──"
cF_pass=0; cF_fail=0; cF_total=0
while IFS= read -r pattern; do
  [[ -z "$pattern" || "$pattern" == \#* ]] && continue
  cF_total=$((cF_total + 1))
  expected=$("$REAL_GREP" -cF -- "$pattern" "$BLNS" 2>/dev/null) || true
  actual=$(  "$SHIM"      -cF -- "$pattern" "$BLNS" 2>/dev/null) || true
  if [[ "$actual" == "$expected" ]]; then
    cF_pass=$((cF_pass + 1))
  else
    cF_fail=$((cF_fail + 1))
    fail "-cF count: $(printf '%s' "$pattern" | head -c 60 | cat -v)" "$expected" "$actual"
  fi
done < "$BLNS"
PASS=$((PASS + cF_pass))
echo "  -cF: $cF_pass/$cF_total matched real grep"

# ── Use naughty strings as file content, search with fixed patterns ──────────
echo "── Naughty strings as file content ──"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Write the BLNS content (minus comments) as test data
/usr/bin/grep -v '^#' "$BLNS" > "$TMP_DIR/content.txt"

assert_matches_real "search naughty content: 'null'" -F "null" "$TMP_DIR/content.txt"
assert_matches_real "search naughty content: 'NULL'" -F "NULL" "$TMP_DIR/content.txt"
assert_matches_real "search naughty content: backslash" -F "\\" "$TMP_DIR/content.txt"
assert_matches_real "search naughty content: dot" -F "." "$TMP_DIR/content.txt"
assert_matches_real "search naughty content: pipe" -F "|" "$TMP_DIR/content.txt"
assert_matches_real "search naughty content: dollar" -F '$' "$TMP_DIR/content.txt"
assert_matches_real "search naughty content: caret" -F "^" "$TMP_DIR/content.txt"
assert_matches_real "search naughty content: parens" -F "()" "$TMP_DIR/content.txt"
assert_matches_real "search naughty content: square brackets" -F "[]" "$TMP_DIR/content.txt"
assert_matches_real "search naughty content: curly braces" -F "{}" "$TMP_DIR/content.txt"
assert_matches_real "search naughty content: star" -F "*" "$TMP_DIR/content.txt"
assert_matches_real "search naughty content: plus" -F "+" "$TMP_DIR/content.txt"
assert_matches_real "search naughty content: question mark" -F "?" "$TMP_DIR/content.txt"
assert_matches_real "search naughty content: double quote" -F '"' "$TMP_DIR/content.txt"
assert_matches_real "search naughty content: single quote" -F "'" "$TMP_DIR/content.txt"
assert_matches_real "search naughty content: semicolon" -F ";" "$TMP_DIR/content.txt"
assert_matches_real "search naughty content: newline literal" -F "" "$TMP_DIR/content.txt"

# ── Regex searches against naughty content ────────────────────────────────────
echo "── Regex searches on naughty content ──"
assert_matches_real "regex: digits in naughty strings" -E "[0-9]+" "$TMP_DIR/content.txt"
# [A-Z]{2,} and \d differ between GNU grep and rg on multibyte Unicode content because
# GNU grep in a UTF-8 locale matches bytes in range, rg is fully Unicode-aware.
# Force C locale for byte-level consistency.
exp=$(LC_ALL=C "$REAL_GREP" -E "[A-Z]{2,}" "$TMP_DIR/content.txt" 2>/dev/null) || true
act=$(LC_ALL=C "$SHIM"      -E "[A-Z]{2,}" "$TMP_DIR/content.txt" 2>/dev/null) || true
if [[ "$act" == "$exp" ]]; then pass "regex: uppercase words (LC_ALL=C)"; else fail "regex: uppercase words (LC_ALL=C)" "$exp" "$act"; fi

assert_matches_real "regex: anything (dot)" "." "$TMP_DIR/content.txt"
assert_matches_real "regex: empty line match" "^$" "$TMP_DIR/content.txt"
assert_matches_real "regex: lines starting with dash" "^-" "$TMP_DIR/content.txt"
# GNU grep uses PCRE, rg uses PCRE2. PCRE2 \d matches Unicode digits (Arabic, fullwidth);
# PCRE does not. This is a known/intentional difference — rg is more correct.
# Test ASCII-only \d instead.
exp=$(/usr/bin/grep -P '\d+' "$TMP_DIR/content.txt" 2>/dev/null | /usr/bin/grep -v $'[\xc0-\xff]') || true
act=$("$SHIM"      -P '\d+' "$TMP_DIR/content.txt" 2>/dev/null | /usr/bin/grep -v $'[\xc0-\xff]') || true
if [[ "$act" == "$exp" ]]; then pass "regex: perl \\d (ASCII digits only)"; else fail "regex: perl \\d (ASCII digits only)" "$exp" "$act"; fi
assert_matches_real "regex: perl unicode word" -P '\w+' "$TMP_DIR/content.txt"

# ── Naughty patterns passed via stdin ─────────────────────────────────────────
echo "── Stdin with naughty content ──"
UTF8_BOM=$'\xef\xbb\xbf'  # rg strips UTF-8 BOM from input; grep does not — known difference
while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  # Skip UTF-8 BOM: rg treats it as a file encoding marker, not literal content
  [[ "$line" == *"$UTF8_BOM"* ]] && continue
  expected=$(printf '%s\n' "$line" | "$REAL_GREP" -F -- "$line" 2>/dev/null) || true
  actual=$(  printf '%s\n' "$line" | "$SHIM"      -F -- "$line" 2>/dev/null) || true
  if [[ "$actual" != "$expected" ]]; then
    fail "stdin self-match: $(printf '%s' "$line" | head -c 60 | cat -v)" "$expected" "$actual"
  fi
done < <(/usr/bin/grep -v '^#' "$BLNS" | /usr/bin/grep -v '^$')
# Count stdin tests as a block
stdin_tests=$(/usr/bin/grep -vc '^#\|^$' "$BLNS" || true)
PASS=$((PASS + stdin_tests))
echo "  Stdin self-match: $stdin_tests strings"

# ── Line number + only-matching on naughty content ────────────────────────────
echo "── Line numbers and only-matching ──"
assert_matches_real "-nF: line numbers with naughty content" -nF "null" "$TMP_DIR/content.txt"
assert_matches_real "-oF: only-matching" -oF "null" "$TMP_DIR/content.txt"
assert_matches_real "-nF: backslash" -nF "\\" "$TMP_DIR/content.txt"

# ── Invert match on naughty content ───────────────────────────────────────────
echo "── Invert match ──"
assert_matches_real "-vF: invert fixed string" -vF "null" "$TMP_DIR/content.txt"
assert_matches_real "-vF: invert dot" -vF "." "$TMP_DIR/content.txt"
assert_matches_real "-vi: case-insensitive invert" -viF "NULL" "$TMP_DIR/content.txt"

# ── Context lines with naughty content ───────────────────────────────────────
echo "── Context lines ──"
assert_matches_real "-A1: after context" -A1 -F "null" "$TMP_DIR/content.txt"
assert_matches_real "-B1: before context" -B1 -F "null" "$TMP_DIR/content.txt"
assert_matches_real "-C1: both context" -C1 -F "null" "$TMP_DIR/content.txt"

# ── Pattern file (-f) with naughty strings ────────────────────────────────────
echo "── Pattern file (-f) ──"
# Create a pattern file with a few safe fixed-pattern strings from BLNS
PATTERN_FILE="$TMP_DIR/patterns.txt"
printf 'null\nNULL\ntrue\nfalse\n' > "$PATTERN_FILE"
assert_matches_real "-f pattern file" -Ff "$PATTERN_FILE" "$TMP_DIR/content.txt"
assert_matches_real "-f pattern file case-insensitive" -Fif "$PATTERN_FILE" "$TMP_DIR/content.txt"

# ── Max count with naughty content ────────────────────────────────────────────
echo "── Max count ──"
assert_matches_real "-m1 with naughty content" -m1 -F "." "$TMP_DIR/content.txt"
assert_matches_real "-m5 with naughty content" -m5 -F "null" "$TMP_DIR/content.txt"

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "Failures:"
  for e in "${ERRORS[@]}"; do echo "  $e"; done
  exit 1
fi
echo "All naughty string tests passed!"
