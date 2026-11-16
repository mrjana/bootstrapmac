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
# GPG Suite also installs /usr/local/bin/gpg. Prefer the same Homebrew
# toolchain as bootstrap, including its keyboxd-capable GPG version.
brew_prefix=/usr/local
[[ "$(uname -m)" == arm64 ]] && brew_prefix=/opt/homebrew
export PATH="$brew_prefix/bin:$brew_prefix/sbin:$PATH"
for cmd in brew codex git gh chezmoi age gpg pass mise zsh; do
  check "Executable: $cmd" command -v "$cmd"
done
check "Codex CLI starts" codex --version
check "GitHub CLI authentication" gh auth status
check "GPG secret key exists" zsh -c 'gpg --list-secret-keys --with-colons 2>/dev/null | grep -q "^sec:"'
check "Password store can decrypt Chezmoi key" zsh -c 'PASSWORD_STORE_GPG_OPTS="--batch --no-tty --pinentry-mode error" pass show chezmoi/age-key >/dev/null 2>&1'
check "Chezmoi health" chezmoi doctor
# A review-branch bootstrap expects the matching dotfiles branch; after merge,
# main expects main. Never silently accept a detached source checkout.
expected_branch="$(git -C "${0:A:h:h}" branch --show-current 2>/dev/null)"
if [[ -z "$expected_branch" ]]; then
  print -u2 "FAIL: bootstrap source is detached or unavailable"
  (( failures += 1 ))
fi
check "Bootstrap review branch" zsh -c '[[ "$(git -C "$1" branch --show-current)" == "$2" ]]' -- "${0:A:h:h}" "$expected_branch"
check "Chezmoi age identity permissions" zsh -c '[[ -s "$HOME/.config/chezmoi/key.txt" && "$(stat -f %Lp "$HOME/.config/chezmoi/key.txt")" == 600 ]]'
if command -v chezmoi >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
  source_dir="$(chezmoi source-path 2>/dev/null)"
  check "Chezmoi review branch" zsh -c '[[ "$(git -C "$1" branch --show-current)" == "$2" ]]' -- "$source_dir" "$expected_branch"
  check "Brewfile exists" test -f "$source_dir/Brewfile"
  if [[ -n "$source_dir" && -f "$source_dir/Brewfile" ]]; then
    check "Brewfile requirements" brew bundle check --file="$source_dir/Brewfile"
    if [[ "$(id -un)" != jradhakr ]]; then
      check "Personal Brewfile exists" test -f "$source_dir/Brewfile.personal"
      check "Personal Brewfile requirements" brew bundle check --file="$source_dir/Brewfile.personal"
    fi
  fi
fi
if command -v mise >/dev/null 2>&1; then
  check "mise global configuration deployed" test -s "$HOME/.config/mise/config.toml"
  # Check the global configuration from HOME, not an unrelated project config.
  check "mise configured runtimes" zsh -c '[[ -s "$HOME/.config/mise/config.toml" ]] && cd "$HOME" && mise install --dry-run-code'
fi
if (( failures > 0 )); then
  print -u2 "$failures verification checks failed"
  exit 1
fi
print "Baseline checks passed. Verify the actual apps and tools you use as well."
