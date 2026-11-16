# Post-merge Mac mini smoke tests

These checks are performed **on the Mac mini**, not by GitHub Actions.
Never paste tokens, decrypted `pass` output or raw environment variables into an AI chat.

## First sync to the merged defaults

After both PRs have merged and local work is safely committed or backed up:

```zsh
git -C ~/bootstrapmac status --short
git -C ~/.local/share/chezmoi status --short
git -C ~/bootstrapmac fetch origin
git -C ~/.local/share/chezmoi fetch origin
```

Only when the working trees are clean, switch each checkout to main and
fast-forward. Do **not** force-reset or discard local changes:

```zsh
git -C ~/bootstrapmac switch main || git -C ~/bootstrapmac switch -c main --track origin/main
git -C ~/bootstrapmac pull --ff-only
git -C ~/.local/share/chezmoi switch main || git -C ~/.local/share/chezmoi switch -c main --track origin/main
git -C ~/.local/share/chezmoi pull --ff-only
```

## Deterministic checks

```zsh
zsh ~/bootstrapmac/scripts/verify-mac.zsh
chezmoi status
brew bundle check --file="$(chezmoi source-path)/Brewfile"
brew bundle check --file="$(chezmoi source-path)/Brewfile.personal"
cd "$HOME" && mise install --dry-run-code
```

Expect all checks to succeed and `chezmoi status` to be empty. If not, fix
the root cause before rerunning `chezmoi apply`. Do not upload raw secret output.

## GUI acceptance (manual)

Use the installed applications, not merely `ls /Applications`, to confirm:

- [ ] **Ghostty or iTerm2:** launch, open a new shell and verify PATH and `mise current`
- [ ] **Chrome:** launch, sign in/sync if desired; verify normal browsing
- [ ] **VS Code:** launch, open a harmless sample folder, open integrated terminal; check extension host and Python/Go tools
- [ ] **Cursor:** launch, open a sample folder and terminal; confirm sign-in and editor operations
- [ ] **Zed:** launch, open/edit/save a scratch file
- [ ] **Warp:** launch, run a harmless shell command
- [ ] **Alfred:** launch and verify hotkey / macOS Accessibility permission if used
- [ ] **Ollama:** launch; test local inference only if a model was explicitly downloaded
- [ ] **GPG Suite:** verify passphrase prompt and agent behavior without exposing secret contents
- [ ] **Tailscale:** launch, authenticate if desired, check intended network connectivity
- [ ] **Apple Configurator:** open to confirm App Store installation, if needed

## Final safety checks

- [ ] No corporate endpoint, login key or hook appears in a personal-shell configuration
- [ ] The expected hostname remains unchanged
- [ ] `chezmoi apply` succeeds a second time and `chezmoi status` is empty
- [ ] A new login shell and noninteractive `zsh -lc` can resolve installed runtimes
- [ ] GitHub SSH and `gh auth status` work, with output kept local

Document PASS/FAIL/NOT TESTED for each item and record the app version and
any actionable error *without* including credentials.
