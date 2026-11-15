#!/usr/bin/env zsh
# Isolated failure-injection tests. Mock EVERY command that could modify a real
# checkout, account, credentials or machine; never invoke actual bootstrap apply.
set -euo pipefail
cd "${0:A:h}/.."
runner="$(mktemp -d)"
trap 'rm -rf "$runner"' EXIT
failures=0

run_case() {
  local scenario="$1" expected="$2"
  local home="$runner/$scenario"
  mkdir -p "$home/.ssh"
  print 'synthetic-key-do-not-use' > "$home/.ssh/id_personal"
  local trace="$home/trace"
  : > "$trace"
  local result=0
  printf 'n\n' | HOME="$home" BOOTSTRAP_TEST_SCENARIO="$scenario" BOOTSTRAP_TEST_TRACE="$trace" \
    zsh -c '
      # All functions run within this test subshell. Actual brew shellenv is
      # invoked by bootstrap using an absolute path; it is read-only.
      function xcode-select() { return 0; }
      function brew() {
        print "brew:$*" >> "$BOOTSTRAP_TEST_TRACE"
        [[ "$BOOTSTRAP_TEST_SCENARIO" != "brew-failure" ]]
      }
      function gpg() {
        print "gpg:$*" >> "$BOOTSTRAP_TEST_TRACE"
        [[ "$BOOTSTRAP_TEST_SCENARIO" == "gpg-failure" ]] && return 1
        print "sec:synthetic"
      }
      function git() {
        print "git:$*" >> "$BOOTSTRAP_TEST_TRACE"
        [[ "$BOOTSTRAP_TEST_SCENARIO" != "git-failure" ]]
      }
      function pass() {
        print "pass:$*" >> "$BOOTSTRAP_TEST_TRACE"
        [[ "$BOOTSTRAP_TEST_SCENARIO" == "pass-failure" ]] && return 1
        print "AGE-SECRET-KEY-SYNTHETIC-TEST-NOT-VALID"
      }
      function chezmoi() {
        print "chezmoi:$*" >> "$BOOTSTRAP_TEST_TRACE"
        [[ "$BOOTSTRAP_TEST_SCENARIO" != "diff-failure" || "$1" != "diff" ]]
      }
      function mise() { print "mise:$*" >> "$BOOTSTRAP_TEST_TRACE"; }
      source ./bootstrap.zsh --apply
    ' > "$home/output" 2>&1 || result=$?
  if [[ "$expected" == failure && "$result" == 0 ]] ||
     [[ "$expected" == success && "$result" != 0 ]]; then
    print -u2 "FAIL: $scenario expected $expected, rc=$result"
    (( failures += 1 ))
  else
    print "PASS: $scenario (rc=$result)"
  fi
  if [[ "$scenario" != "diff-failure" ]] && grep -q '^mise:' "$trace"; then
    print -u2 "FAIL: $scenario unexpectedly installed runtimes"
    (( failures += 1 ))
  fi
  if [[ "$scenario" == "diff-failure" ]] && grep -q '^chezmoi:apply' "$trace"; then
    print -u2 "FAIL: failed diff continued to apply"
    (( failures += 1 ))
  fi
  if [[ "$scenario" == "brew-failure" ]] && grep -q '^chezmoi:' "$trace"; then
    print -u2 "FAIL: failed brew continued to chezmoi"
    (( failures += 1 ))
  fi
  # No secret or the synthetic token should appear in output.
  if grep -q 'AGE-SECRET-KEY-SYNTHETIC' "$home/output"; then
    print -u2 "FAIL: token leaked to stdout/stderr"
    (( failures += 1 ))
  fi
}
run_case brew-failure failure
run_case gpg-failure failure
run_case git-failure failure
run_case pass-failure failure
run_case diff-failure failure
run_case user-declines success

if (( failures )); then
  print -u2 "$failures cases failed"
  exit 1
fi
print 'All mocked failure-injection cases passed.'
