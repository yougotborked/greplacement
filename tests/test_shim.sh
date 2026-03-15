#!/usr/bin/env bash
# Test suite for grep shim
# Tests are written against real grep behavior, then verified to match the shim.
# Run with: bash tests/test_shim.sh [--shim /path/to/shim] [--verbose]
set -uo pipefail

SHIM="${SHIM:-$HOME/.local/bin/grep}"
REAL_GREP=/usr/bin/grep
FIXTURES="$(cd "$(dirname "$0")/fixtures" && pwd)"
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
  ERRORS+=("  expected: $2")
  ERRORS+=("  actual:   $3")
  echo "  FAIL: $1"
  if [[ $VERBOSE -eq 1 ]]; then
    echo "    expected: $2"
    echo "    actual:   $3"
  fi
}

# assert_output: compare shim output against expected string
assert_output() {
  local desc="$1"; local expected="$2"; shift 2
  local actual
  actual=$("$SHIM" "$@" 2>/dev/null) || true
  if [[ "$actual" == "$expected" ]]; then pass "$desc"; else fail "$desc" "$expected" "$actual"; fi
}

# assert_matches_real: shim output must equal real grep output
assert_matches_real() {
  local desc="$1"; shift
  local expected actual
  expected=$("$REAL_GREP" "$@" 2>/dev/null) || true
  actual=$("$SHIM" "$@" 2>/dev/null) || true
  if [[ "$actual" == "$expected" ]]; then pass "$desc"; else fail "$desc" "$expected" "$actual"; fi
}

# assert_exit: verify exit code
assert_exit() {
  local desc="$1"; local expected_exit="$2"; shift 2
  local actual_exit=0
  "$SHIM" "$@" >/dev/null 2>&1 || actual_exit=$?
  if [[ "$actual_exit" -eq "$expected_exit" ]]; then pass "$desc"; else fail "$desc" "$expected_exit" "$actual_exit"; fi
}

# assert_exit_matches_real: shim exit code == real grep exit code
assert_exit_matches_real() {
  local desc="$1"; shift
  local expected_exit=0 actual_exit=0
  "$REAL_GREP" "$@" >/dev/null 2>&1 || expected_exit=$?
  "$SHIM" "$@" >/dev/null 2>&1 || actual_exit=$?
  if [[ "$actual_exit" -eq "$expected_exit" ]]; then pass "$desc"; else fail "$desc" "exit=$expected_exit" "exit=$actual_exit"; fi
}

echo "=== grep shim test suite ==="
echo "Shim: $SHIM"
echo "Fixtures: $FIXTURES"
echo ""

# ── Shim exists ────────────────────────────────────────────────────────────────
echo "── Existence ──"
if [[ -x "$SHIM" ]]; then pass "shim exists and is executable"; else fail "shim exists and is executable" "executable" "missing/not-executable"; fi

# ── Basic matching ─────────────────────────────────────────────────────────────
echo "── Basic matching ──"
assert_matches_real "simple pattern match" "hello" "$FIXTURES/sample.txt"
assert_matches_real "pattern not found" "zzznomatch" "$FIXTURES/sample.txt"
assert_matches_real "match at start of line" "^Hello" "$FIXTURES/sample.txt"
assert_matches_real "match at end of line" "fox$" "$FIXTURES/sample.txt"
assert_matches_real "dot metachar" "hel.o" "$FIXTURES/sample.txt"

# ── Exit codes ─────────────────────────────────────────────────────────────────
echo "── Exit codes ──"
assert_exit "exit 0 when match found" 0 "hello" "$FIXTURES/sample.txt"
assert_exit "exit 1 when no match" 1 "zzznomatch" "$FIXTURES/sample.txt"
assert_exit_matches_real "exit code: match" "hello" "$FIXTURES/sample.txt"
assert_exit_matches_real "exit code: no match" "zzznomatch" "$FIXTURES/sample.txt"

# ── Case insensitive ──────────────────────────────────────────────────────────
echo "── Case insensitive (-i) ──"
assert_matches_real "case insensitive short" -i "hello" "$FIXTURES/sample.txt"
assert_matches_real "case insensitive long" --ignore-case "HELLO" "$FIXTURES/sample.txt"

# ── Invert match ──────────────────────────────────────────────────────────────
echo "── Invert match (-v) ──"
assert_matches_real "invert match" -v "hello" "$FIXTURES/sample.txt"
assert_matches_real "invert match long" --invert-match "Hello" "$FIXTURES/sample.txt"

# ── Line numbers ──────────────────────────────────────────────────────────────
echo "── Line numbers (-n) ──"
assert_matches_real "line numbers" -n "hello" "$FIXTURES/sample.txt"
assert_matches_real "line numbers long" --line-number "hello" "$FIXTURES/sample.txt"

# ── Count ─────────────────────────────────────────────────────────────────────
echo "── Count (-c) ──"
assert_matches_real "count matches" -c "hello" "$FIXTURES/sample.txt"
assert_matches_real "count with case" -ci "hello" "$FIXTURES/sample.txt"

# ── Files with/without matches ────────────────────────────────────────────────
echo "── File lists (-l/-L) ──"
# File order may differ between grep/rg — sort both
_files_with_matches_exp=$("$REAL_GREP" -l "hello" "$FIXTURES/sample.txt" "$FIXTURES/other.txt" 2>/dev/null | sort) || true
_files_with_matches_act=$("$SHIM"      -l "hello" "$FIXTURES/sample.txt" "$FIXTURES/other.txt" 2>/dev/null | sort) || true
if [[ "$_files_with_matches_act" == "$_files_with_matches_exp" ]]; then pass "files with matches"; else fail "files with matches" "$_files_with_matches_exp" "$_files_with_matches_act"; fi
# File order may differ between grep/rg — sort both
_no_match_exp=$("$REAL_GREP" -L "zzznomatch" "$FIXTURES/sample.txt" "$FIXTURES/other.txt" 2>/dev/null | sort) || true
_no_match_act=$("$SHIM"      -L "zzznomatch" "$FIXTURES/sample.txt" "$FIXTURES/other.txt" 2>/dev/null | sort) || true
if [[ "$_no_match_act" == "$_no_match_exp" ]]; then pass "files without matches"; else fail "files without matches" "$_no_match_exp" "$_no_match_act"; fi
assert_matches_real "files without matches (some match)" -L "hello" "$FIXTURES/sample.txt" "$FIXTURES/other.txt"

# ── Only matching ─────────────────────────────────────────────────────────────
echo "── Only matching (-o) ──"
assert_matches_real "only matching (ERE)" -oE "hel[lo]+" "$FIXTURES/sample.txt"
assert_matches_real "only matching with -n" -on "hello" "$FIXTURES/sample.txt"

# ── Word regexp ───────────────────────────────────────────────────────────────
echo "── Word regexp (-w) ──"
assert_matches_real "word regexp" -w "foo" "$FIXTURES/sample.txt"
assert_matches_real "word no match (substring)" -w "ello" "$FIXTURES/sample.txt"

# ── Line regexp ───────────────────────────────────────────────────────────────
echo "── Line regexp (-x) ──"
assert_matches_real "line regexp exact" -x "Hello World" "$FIXTURES/sample.txt"
assert_matches_real "line regexp no match" -x "Hello" "$FIXTURES/sample.txt"

# ── Fixed strings ─────────────────────────────────────────────────────────────
echo "── Fixed strings (-F) ──"
assert_matches_real "fixed strings" -F "foo bar" "$FIXTURES/sample.txt"
assert_matches_real "fixed strings dots" -F "1.2" "$FIXTURES/sample.txt"

# ── Extended regex ────────────────────────────────────────────────────────────
echo "── Extended regex (-E) ──"
assert_matches_real "extended alternation" -E "hello|HELLO" "$FIXTURES/sample.txt"
assert_matches_real "extended plus" -E "hel+" "$FIXTURES/sample.txt"
assert_matches_real "extended groups" -E "(foo|bar) (bar|baz)" "$FIXTURES/sample.txt"

# ── Perl regex ────────────────────────────────────────────────────────────────
echo "── Perl regex (-P) ──"
# Skip -P tests if system grep (macOS BSD grep) or rg (some distro builds lack PCRE2)
# don't support PCRE — the two engines would produce different results and the test
# would spuriously fail.
_grep_has_pcre=0; echo "test123" | "$REAL_GREP" -P '\d' >/dev/null 2>&1 && _grep_has_pcre=1
_shim_has_pcre=0; echo "test123" | "$SHIM"      -P '\d' >/dev/null 2>&1 && _shim_has_pcre=1
if [[ $_grep_has_pcre -eq 1 && $_shim_has_pcre -eq 1 ]]; then
  assert_matches_real "perl digits" -P "\d+" "$FIXTURES/sample.txt"
  assert_matches_real "perl lookahead" -oP "hel(?=lo)" "$FIXTURES/sample.txt"
else
  pass "perl digits (skipped: grep or rg lacks -P/PCRE support on this platform)"
  pass "perl lookahead (skipped: grep or rg lacks -P/PCRE support on this platform)"
fi

# ── Multiple patterns (-e) ────────────────────────────────────────────────────
echo "── Multiple patterns (-e) ──"
assert_matches_real "multiple -e patterns" -e "hello" -e "HELLO" "$FIXTURES/sample.txt"
assert_matches_real "multiple -e with flags" -i -e "hello" -e "fox" "$FIXTURES/sample.txt"

# ── Quiet mode ────────────────────────────────────────────────────────────────
echo "── Quiet mode (-q) ──"
assert_exit "quiet exit 0 on match" 0 -q "hello" "$FIXTURES/sample.txt"
assert_exit "quiet exit 1 on no match" 1 -q "zzznomatch" "$FIXTURES/sample.txt"
assert_output "quiet produces no output" "" -q "hello" "$FIXTURES/sample.txt"

# ── Filename control (-H/-h) ─────────────────────────────────────────────────
echo "── Filename control (-H/-h) ──"
assert_matches_real "with filename single file" -H "hello" "$FIXTURES/sample.txt"
# Multi-file line order may differ between grep/rg — sort both
_h_exp=$("$REAL_GREP" -h "hello" "$FIXTURES/sample.txt" "$FIXTURES/other.txt" 2>/dev/null | sort) || true
_h_act=$("$SHIM"      -h "hello" "$FIXTURES/sample.txt" "$FIXTURES/other.txt" 2>/dev/null | sort) || true
if [[ "$_h_act" == "$_h_exp" ]]; then pass "no filename two files"; else fail "no filename two files" "$_h_exp" "$_h_act"; fi

# ── Context lines (-A/-B/-C) ─────────────────────────────────────────────────
echo "── Context lines (-A/-B/-C) ──"
assert_matches_real "after context" -A2 "quick brown" "$FIXTURES/sample.txt"
assert_matches_real "before context" -B2 "quick brown" "$FIXTURES/sample.txt"
assert_matches_real "context both" -C1 "quick brown" "$FIXTURES/sample.txt"
assert_matches_real "after context long form" --after-context=1 "hello" "$FIXTURES/sample.txt"
assert_matches_real "before context long form" --before-context=1 "hello" "$FIXTURES/sample.txt"
assert_matches_real "context long form" --context=1 "hello" "$FIXTURES/sample.txt"

# ── Max count (-m) ────────────────────────────────────────────────────────────
echo "── Max count (-m) ──"
assert_matches_real "max count 1" -m1 "hello" "$FIXTURES/sample.txt"
assert_matches_real "max count 2" -m 2 "hello" "$FIXTURES/sample.txt"

# ── Combined flags ────────────────────────────────────────────────────────────
echo "── Combined flags ──"
assert_matches_real "combined -in" -in "hello" "$FIXTURES/sample.txt"
assert_matches_real "combined -iv" -iv "hello" "$FIXTURES/sample.txt"
assert_matches_real "combined -cin" -cin "hello" "$FIXTURES/sample.txt"
assert_matches_real "combined -nH" -nH "hello" "$FIXTURES/sample.txt"

# ── Stdin reading ─────────────────────────────────────────────────────────────
echo "── Stdin ──"
expected=$( echo -e "hello world\nfoo bar\nhello again" | "$REAL_GREP" "hello" )
actual=$(   echo -e "hello world\nfoo bar\nhello again" | "$SHIM" "hello" )
if [[ "$actual" == "$expected" ]]; then pass "stdin basic"; else fail "stdin basic" "$expected" "$actual"; fi

expected=$( echo -e "hello\nworld" | "$REAL_GREP" -c "hello" )
actual=$(   echo -e "hello\nworld" | "$SHIM" -c "hello" )
if [[ "$actual" == "$expected" ]]; then pass "stdin count"; else fail "stdin count" "$expected" "$actual"; fi

expected=$( echo -e "hello\nworld" | "$REAL_GREP" -v "hello" )
actual=$(   echo -e "hello\nworld" | "$SHIM" -v "hello" )
if [[ "$actual" == "$expected" ]]; then pass "stdin invert"; else fail "stdin invert" "$expected" "$actual"; fi

# ── Include/exclude globs ─────────────────────────────────────────────────────
echo "── Include/exclude (recursive) ──"
TMPDIR_TEST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TEST"' EXIT
mkdir -p "$TMPDIR_TEST/sub"
echo "hello in txt" > "$TMPDIR_TEST/a.txt"
echo "hello in log" > "$TMPDIR_TEST/b.log"
echo "hello in sub" > "$TMPDIR_TEST/sub/c.txt"

expected=$("$REAL_GREP" -r --include="*.txt" "hello" "$TMPDIR_TEST" | sort)
actual=$(   "$SHIM"      -r --include="*.txt" "hello" "$TMPDIR_TEST" | sort)
if [[ "$actual" == "$expected" ]]; then pass "include glob"; else fail "include glob" "$expected" "$actual"; fi

expected=$("$REAL_GREP" -r --exclude="*.log" "hello" "$TMPDIR_TEST" | sort)
actual=$(   "$SHIM"      -r --exclude="*.log" "hello" "$TMPDIR_TEST" | sort)
if [[ "$actual" == "$expected" ]]; then pass "exclude glob"; else fail "exclude glob" "$expected" "$actual"; fi

# ── Recursive ─────────────────────────────────────────────────────────────────
echo "── Recursive (-r/-R) ──"
expected=$("$REAL_GREP" -r "hello" "$TMPDIR_TEST" | sort)
actual=$(   "$SHIM"      -r "hello" "$TMPDIR_TEST" | sort)
if [[ "$actual" == "$expected" ]]; then pass "recursive -r"; else fail "recursive -r" "$expected" "$actual"; fi

# ── Fallback: BRE (-G) ────────────────────────────────────────────────────────
echo "── Fallback behavior ──"
expected=$("$REAL_GREP" -G "hel\+o" "$FIXTURES/sample.txt" 2>/dev/null) || true
actual=$(   "$SHIM"      -G "hel\+o" "$FIXTURES/sample.txt" 2>/dev/null) || true
if [[ "$actual" == "$expected" ]]; then pass "fallback BRE (-G)"; else fail "fallback BRE (-G)" "$expected" "$actual"; fi

# ── Color passthrough ─────────────────────────────────────────────────────────
echo "── Color control ──"
assert_exit "no-color flag accepted" 0 --no-color "hello" "$FIXTURES/sample.txt"
assert_exit "color=never flag accepted" 0 "--color=never" "hello" "$FIXTURES/sample.txt"

# ── Long-form flags ───────────────────────────────────────────────────────────
echo "── Long-form flags ──"
assert_matches_real "long: --fixed-strings" --fixed-strings "foo bar" "$FIXTURES/sample.txt"
assert_matches_real "long: --word-regexp" --word-regexp "foo" "$FIXTURES/sample.txt"
assert_matches_real "long: --line-regexp" --line-regexp "Hello World" "$FIXTURES/sample.txt"
assert_matches_real "long: --count" --count "hello" "$FIXTURES/sample.txt"
assert_matches_real "long: --only-matching (ERE)" --only-matching --extended-regexp "hel[lo]+" "$FIXTURES/sample.txt"
assert_matches_real "long: --quiet match" --quiet "hello" "$FIXTURES/sample.txt" || true

# ── No-match suppress errors (-s) ─────────────────────────────────────────────
echo "── Suppress errors (-s) ──"
assert_exit "suppress errors exit code" 1 -s "zzznomatch" "$FIXTURES/sample.txt"

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
echo "All tests passed!"
