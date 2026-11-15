#!/usr/bin/env zsh
# Read-only post-bootstrap checks. Does not print decrypted secrets.
set -u
failures=0
check() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    print "PASS: $description"
  else
    print -u2 "FAIL: $description"
    (( failures += 1 ))
  fi
}
[[ "$(uname -s)" == Darwin ]] || { print -u2 "Only macOS is supported"; exit 1; }
for cmd in brew codex git gh chezmoi age gpg pass mise zsh; do
  check "Executable: $cmd" command -v "$cmd"
done
check "Codex CLI starts" codex --version
check "GitHub CLI authentication" gh auth status
check "GPG secret key exists" zsh -c 'gpg --list-secret-keys --with-colons 2>/dev/null | grep -q "^sec:"'
check "Password store can decrypt Chezmoi key" zsh -c 'PASSWORD_STORE_GPG_OPTS="--batch --no-tty --pinentry-mode error" pass show chezmoi/age-key >/dev/null 2>&1'
check "Chezmoi health" chezmoi doctor
if command -v chezmoi >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
  source_dir="$(chezmoi source-path 2>/dev/null)"
  if [[ -n "$source_dir" && -f "$source_dir/Brewfile" ]]; then
    check "Brewfile requirements" brew bundle check --file="$source_dir/Brewfile"
  fi
fi
if command -v mise >/dev/null 2>&1; then
  check "mise configured runtimes" mise install --dry-run-code
fi
if (( failures > 0 )); then
  print -u2 "$failures verification checks failed"
  exit 1
fi
print "Baseline checks passed. Verify the actual apps and tools you use as well."
