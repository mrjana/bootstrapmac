#!/usr/bin/env zsh
# Safe, resumable macOS bootstrap. Run with --apply after reviewing the plan.
set -euo pipefail

usage() {
  print "Usage: ./bootstrap.zsh [--apply]"
  print "Without --apply, print the recovery sequence and exit."
}
apply=false
case "${1:-}" in
  "") ;;
  --apply) apply=true ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

[[ "$(uname -s)" == Darwin ]] || { print -u2 "ERROR: macOS is required"; exit 1; }
arch="$(uname -m)"
[[ "$arch" == arm64 || "$arch" == x86_64 ]] || { print -u2 "ERROR: unsupported architecture: $arch"; exit 1; }

print "Bootstrap steps: developer tools, Homebrew, recovery keys, private GitHub repos,"
print "password-store/age identity, chezmoi review, then Homebrew and mise packages."
print "Review the recovery instructions at https://github.com/mrjana/dotfiles/blob/main/README.md"
if [[ "$apply" != true ]]; then
  print "Planning only. Re-run with --apply to make changes."
  exit 0
fi

if ! xcode-select -p >/dev/null 2>&1; then
  print -u2 "Apple command line developer tools are required."
  xcode-select --install || true
  print -u2 "Complete Apple's installer, then rerun this script."
  exit 1
fi

brew_prefix=/usr/local
[[ "$arch" == arm64 ]] && brew_prefix=/opt/homebrew
if [[ ! -x "$brew_prefix/bin/brew" ]]; then
  print "Homebrew is missing. Review the official installer before proceeding."
  read -r "answer?Install Homebrew from brew.sh now? [y/N] "
  [[ "$answer" == [yY] ]] || exit 1
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
[[ -x "$brew_prefix/bin/brew" ]] || { print -u2 "ERROR: Homebrew not found"; exit 1; }
eval "$("$brew_prefix/bin/brew" shellenv)"

# Essentials needed BEFORE chezmoi can render templates or run hooks.
brew install age gnupg pass chezmoi git gh

if [[ ! -f "$HOME/.ssh/id_personal" ]]; then
  print -u2 "ERROR: restore ~/.ssh/id_personal from the age-encrypted iCloud backup first."
  print -u2 "See dotfiles README, 'Restore keys from iCloud Drive'."
  exit 1
fi
chmod 700 "$HOME/.ssh"
chmod 600 "$HOME/.ssh/id_personal"
if ! gpg --list-secret-keys --with-colons 2>/dev/null | grep -q '^sec:'; then
  print -u2 "ERROR: restore your GPG private key from iCloud before continuing."
  exit 1
fi

# Avoid depending on the chezmoi-managed ~/.ssh/config before chezmoi is applied.
if ! GIT_SSH_COMMAND="ssh -i $HOME/.ssh/id_personal -o IdentitiesOnly=yes" \
    git ls-remote git@github.com:mrjana/dotfiles.git HEAD >/dev/null; then
  print -u2 "ERROR: GitHub SSH authentication for mrjana/dotfiles failed."
  exit 1
fi

if [[ ! -d "$HOME/.password-store/.git" ]]; then
  GIT_SSH_COMMAND="ssh -i $HOME/.ssh/id_personal -o IdentitiesOnly=yes" \
    git clone git@github.com:mrjana/password-store.git "$HOME/.password-store"
fi

# No decrypted secret should be passed to the terminal, logs, or the AI agent.
age_key="$HOME/.config/chezmoi/key.txt"
if [[ ! -s "$age_key" ]]; then
  (umask 077
   mkdir -p "$HOME/.config/chezmoi"
   temp_key="$(mktemp "$HOME/.config/chezmoi/.key.XXXXXX")"
   trap 'rm -f "$temp_key"' EXIT
   pass show chezmoi/age-key > "$temp_key"
   [[ -s "$temp_key" ]] || exit 1
   mv "$temp_key" "$age_key"
  ) || { print -u2 "ERROR: unable to retrieve chezmoi age identity"; exit 1; }
fi
chmod 600 "$age_key"

GIT_SSH_COMMAND="ssh -i $HOME/.ssh/id_personal -o IdentitiesOnly=yes" chezmoi init --ssh mrjana
print "Review the proposed changes; hooks may install software or change macOS settings."
chezmoi diff
read -r "answer?Apply the chezmoi configuration and run its hooks? [y/N] "
[[ "$answer" == [yY] ]] || { print "Changes not applied."; exit 0; }
chezmoi apply -v

# Runtime installation is separate from installing the mise executable.
mise install
chezmoi doctor
print "Bootstrap completed. Confirm: brew bundle check --file=$(chezmoi source-path)/Brewfile"
