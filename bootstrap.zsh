#!/usr/bin/env zsh

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Detect CPU architecture
ARCH=$(uname -m)

# Set Homebrew path based on architecture
if [[ "$ARCH" == "arm64" ]]; then
    BREW_PREFIX="/opt/homebrew"
else
    BREW_PREFIX="/usr/local"
fi

# Ensure Homebrew binary is in PATH
if [[ -d "$BREW_PREFIX/bin" ]]; then
    export PATH="$BREW_PREFIX/bin:$PATH"
    eval "$($BREW_PREFIX/bin/brew shellenv)"
    echo "Homebrew is set up at $BREW_PREFIX"
else
    echo "Homebrew not found at expected location ($BREW_PREFIX)."
    exit 1
fi

brew install chezmoi
brew install --cask git-credential-manager
mkdir -p ~/.local/share
chezmoi init mrjana --apply
