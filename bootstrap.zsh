#!/usr/bin/env zsh

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install chezmoi
brew install --cask git-credential-manager
mkdir -p ~/.local/share
git clone https://github.com/mrjana/dotfiles.git ~/.local/share/chezmoi
chezmoi init --apply