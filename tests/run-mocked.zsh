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
  mkdir -p "$home/.ssh" "$home/mockbin"
  print 'synthetic-key-do-not-use' > "$home/.ssh/id_personal"
  local trace="$home/trace"
  : > "$trace"
  local result=0
  local reply=n
  [[ "$scenario" == apply-failure || "$scenario" == mise-failure ]] && reply=y
  printf 'y\n%s\n' "$reply" | HOME="$home" PATH="$home/mockbin:$PATH" BOOTSTRAP_TEST_SCENARIO="$scenario" BOOTSTRAP_TEST_TRACE="$trace" \
    zsh -c '
      # All functions run within this test subshell. Actual brew shellenv is
      # invoked by bootstrap using an absolute path; it is read-only.
      function command() {
        if [[ "$BOOTSTRAP_TEST_SCENARIO" == "codex-install-failure" && "$*" == "-v codex" ]]; then
          return 1
        fi
        builtin command "$@"
      }
      function xcode-select() { return 0; }
      function brew() {
        print "brew:$*" >> "$BOOTSTRAP_TEST_TRACE"
        [[ "$BOOTSTRAP_TEST_SCENARIO" == "brew-failure" ]] && return 1
        if [[ "$*" == "install --cask codex" ]]; then
          [[ "$BOOTSTRAP_TEST_SCENARIO" == "codex-install-failure" ]] && return 1
          printf "#!/bin/sh\necho codex-test-version\n" > "$HOME/mockbin/codex"
          chmod +x "$HOME/mockbin/codex"
        fi
        return 0
      }
      function gpg() {
        print "gpg:$*" >> "$BOOTSTRAP_TEST_TRACE"
        [[ "$BOOTSTRAP_TEST_SCENARIO" == "gpg-failure" ]] && return 1
        print "sec:synthetic"
      }
      function git() {
        print "git:$*" >> "$BOOTSTRAP_TEST_TRACE"
        if [[ "$*" == *"branch --show-current"* ]]; then print main; return 0; fi
        [[ "$BOOTSTRAP_TEST_SCENARIO" == "git-failure" ]] && return 1
        if [[ "$1" == clone ]]; then
          mkdir -p "$HOME/.password-store/.git"
        fi
        return 0
      }
      function pass() {
        [[ "$(readlink "$HOME/.local/libexec/pass-gpg/gpg2")" == /opt/homebrew/bin/gpg || "$(readlink "$HOME/.local/libexec/pass-gpg/gpg2")" == /usr/local/bin/gpg ]] || return 91
        [[ "$(builtin command -v gpg2)" == "$HOME/.local/libexec/pass-gpg/gpg2" ]] || return 92
        print "pass:$*" >> "$BOOTSTRAP_TEST_TRACE"
        [[ "$BOOTSTRAP_TEST_SCENARIO" == "pass-failure" ]] && return 1
        print "AGE-SECRET-KEY-SYNTHETIC-TEST-NOT-VALID"
      }
      function chezmoi() {
        print "chezmoi:$*" >> "$BOOTSTRAP_TEST_TRACE"
        if [[ "$BOOTSTRAP_TEST_SCENARIO" == "diff-failure" && "$1" == "status" ]]; then return 1; fi
        if [[ "$BOOTSTRAP_TEST_SCENARIO" == "apply-failure" && "$1" == "apply" ]]; then return 1; fi
        return 0
      }
      function mise() {
        print "mise:$*" >> "$BOOTSTRAP_TEST_TRACE"
        [[ "$BOOTSTRAP_TEST_SCENARIO" != "mise-failure" ]]
      }
      source ./bootstrap.zsh --apply
    ' > "$home/output" 2>&1 || result=$?
  if [[ "$expected" == failure && "$result" == 0 ]] ||
     [[ "$expected" == success && "$result" != 0 ]]; then
    print -u2 "FAIL: $scenario expected $expected, rc=$result"
    sed -E "s/AGE-SECRET-KEY-[A-Z0-9-]+/[REDACTED]/g" "$home/output" | tail -n 12 >&2
    (( failures += 1 ))
  else
    print "PASS: $scenario (rc=$result)"
  fi
  if [[ "$scenario" != "mise-failure" ]] && grep -q '^mise:' "$trace"; then
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
  if [[ "$expected" == failure ]] && grep -q 'Bootstrap completed' "$home/output"; then
    print -u2 "FAIL: $scenario reported success despite an injected failure"
    (( failures += 1 ))
  fi
  # No secret or the synthetic token should appear in output.
  if grep -q 'AGE-SECRET-KEY-SYNTHETIC' "$home/output"; then
    print -u2 "FAIL: token leaked to stdout/stderr"
    (( failures += 1 ))
  fi
}
run_case brew-failure failure
run_case codex-install-failure failure
run_case gpg-failure failure
run_case git-failure failure
run_case pass-failure failure
run_case diff-failure failure
run_case apply-failure failure
run_case mise-failure failure
run_case user-declines success


# Happy path, then repeat against the same isolated home. The second execution
# must not re-clone the password store or re-decrypt/write the age key.
test_home="$runner/repeat"
mkdir -p "$test_home/.ssh" "$test_home/mockbin"
print 'synthetic-key-do-not-use' > "$test_home/.ssh/id_personal"
: > "$test_home/trace"
mock_driver() {
  local home="$1"
  HOME="$home" PATH="$home/mockbin:$PATH" BOOTSTRAP_TEST_TRACE="$home/trace" zsh -c '
    function xcode-select() { return 0; }
    function brew() {
      print "brew:$*" >> "$BOOTSTRAP_TEST_TRACE"
      if [[ "$*" == "install --cask codex" ]]; then
        printf "#!/bin/sh\necho codex-test-version\n" > "$HOME/mockbin/codex"
        chmod +x "$HOME/mockbin/codex"
      fi
      return 0
    }
    function gpg() { print "sec:synthetic"; }
    function git() {
      print "git:$*" >> "$BOOTSTRAP_TEST_TRACE"
      if [[ "$*" == *"branch --show-current"* ]]; then print main; return 0; fi
      if [[ "$1" == clone ]]; then mkdir -p "$HOME/.password-store/.git"; fi
    }
    function pass() {
        [[ "$(readlink "$HOME/.local/libexec/pass-gpg/gpg2")" == /opt/homebrew/bin/gpg || "$(readlink "$HOME/.local/libexec/pass-gpg/gpg2")" == /usr/local/bin/gpg ]] || return 91
        [[ "$(builtin command -v gpg2)" == "$HOME/.local/libexec/pass-gpg/gpg2" ]] || return 92
      print "pass:$*" >> "$BOOTSTRAP_TEST_TRACE"
      print "AGE-SECRET-KEY-SYNTHETIC-TEST-NOT-VALID"
    }
    function chezmoi() { print "chezmoi:$*" >> "$BOOTSTRAP_TEST_TRACE"; }
    function mise() { print "mise:$*" >> "$BOOTSTRAP_TEST_TRACE"; }
    source ./bootstrap.zsh --apply
  ' <<< $'y\ny'
}
mock_driver "$test_home" > "$test_home/first.out" 2>&1 || {
  print -u2 "FAIL: mocked successful bootstrap"; tail -n 12 "$test_home/first.out" >&2; (( failures += 1 ))
}
if [[ ! -s "$test_home/.config/chezmoi/key.txt" ]]; then
  print -u2 "FAIL: missing recovered age key"; (( failures += 1 ))
fi
: > "$test_home/trace"
mock_driver "$test_home" > "$test_home/second.out" 2>&1 || {
  print -u2 "FAIL: mocked second bootstrap"; (( failures += 1 ))
}
if grep -Eq '^(pass:|git:clone|brew:install --cask codex)' "$test_home/trace"; then
  print -u2 "FAIL: repeated recovery or clone on rerun"; (( failures += 1 ))
else
  print "PASS: mocked safe rerun skips recovered credentials"
fi
if grep -q 'AGE-SECRET-KEY-SYNTHETIC' "$test_home/first.out" "$test_home/second.out"; then
  print -u2 "FAIL: secret exposed to stdout"; (( failures += 1 ))
fi

if (( failures )); then
  print -u2 "$failures cases failed"
  exit 1
fi
print 'All mocked failure-injection cases passed.'
