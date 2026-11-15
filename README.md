# bootstrapmac

Reproducible macOS development bootstrap. This public repository prepares a new Mac
for the private [mrjana/dotfiles](https://github.com/mrjana/dotfiles) Chezmoi
configuration. **Review the script before executing it.**

## Recovery prerequisites

- A macOS account with access to iCloud key backups and the backup age passphrase.
- Your personal GitHub SSH private key and GPG private key, recovered from age-encrypted
  iCloud backups. See the private dotfiles README for the restore commands.
- Apple command-line developer tools: `xcode-select --install`.

The script installs minimal Homebrew tooling, then *stops with instructions* if keys
or private-repository access are unavailable. It does not request or print secrets.

## Usage

Clone the repository after installing the developer tools:

```zsh
git clone https://github.com/mrjana/bootstrapmac.git ~/bootstrapmac
cd ~/bootstrapmac
zsh bootstrap.zsh             # review plan, no modifications
zsh bootstrap.zsh --apply     # staged installation and an approval gate
```

The apply command:
1. Installs Homebrew if necessary (asks for permission).
2. Installs age, GPG, pass, git, gh and chezmoi.
3. Verifies restored SSH/GPG keys and private GitHub repository access.
4. Clones password-store using a direct GitHub SSH URL if absent.
5. Restores the Chezmoi age identity from pass with restrictive permissions.
6. Initializes Chezmoi via SSH, shows `chezmoi diff`, and requests approval.
7. Applies dotfiles/hooks, installs mise runtimes and runs `chezmoi doctor`.

```zsh
zsh scripts/verify-mac.zsh
```

The verifier does not print secret values. It checks installed tools, authentication
and package/runtime state but cannot independently certify personal application setup.

## Safety and platform limitations

- macOS ARM64 and Intel are supported by the script's path detection.
- No system defaults or applications change in planning mode.
- Chezmoi's approved application phase installs programs and changes user preferences.
- GitHub authentication and GPG decryption require interactive owner involvement.
- Do not pass recovered keys or tokens into AI tools, logs or GitHub Actions.
- The script is resumable, but on-machine testing is required before declaring it
  fully idempotent. The GitHub Actions job covers syntax and planning mode only.
- For a personal machine, choose an account name other than `jradhakr`, or adjust
  the work-account conditional in dotfiles before applying; the legacy dotfiles
  currently use this username to distinguish corporate configuration.
