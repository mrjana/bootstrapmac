#!/usr/bin/env zsh
# Exercise the actual bootstrap setup block against isolated Homebrew fixtures.
set -euo pipefail
cd "${0:A:h}/.."
runner=$(mktemp -d)
trap 'rm -rf "$runner"' EXIT
for architecture in arm64 x86_64; do
  home="$runner/$architecture"
  mkdir -p "$home/brew/bin" "$home/MacGPG2/bin"
  printf '#!/bin/sh\necho homebrew\n' > "$home/brew/bin/gpg"
  printf '#!/bin/sh\nexit 99\n' > "$home/MacGPG2/bin/gpg2"
  chmod +x "$home/brew/bin/gpg" "$home/MacGPG2/bin/gpg2"
  block=$(sed -n '/^# pass selects gpg2/,/^rehash/p' bootstrap.zsh)
  HOME="$home" PATH="$home/MacGPG2/bin:/usr/bin:/bin" zsh -c '
    set -euo pipefail
    brew_prefix="$HOME/brew"
    eval "$1"
    [[ "$(gpg2 --version)" == homebrew ]]
    eval "$1"
    [[ "$(readlink "$HOME/.local/libexec/pass-gpg/gpg2")" == "$brew_prefix/bin/gpg" ]]
  ' -- "$block"
  print "PASS: $architecture bootstrap shim overrides MacGPG2 and is repeatable"
done
