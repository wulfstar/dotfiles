# Repository Guide

## Architecture

- `dotfiles.sh` is sourced entrypoint. It exports `DOTFILES_DIR`, defines shared helpers and `d-help`, then sources every `commands/*.sh` file.
- Public commands are Bash functions named `d-*`; internal helpers use `_dot_*` so command discovery excludes them.
- Add commands to fitting `commands/<topic>.sh`. No registry or dispatcher update is needed.
- `d-help` extracts descriptions only from exact declarations shaped like `d-name() { # Description`; declarations without inline comments load but show blank help text. An optional `: d-name <args>` suffix on that comment is the usage string, shown only by `d-help <group>` and `d-help <command>`.
- Each file is one `d-help` group: `dotfiles.sh` first, then `commands/*.sh` alphabetically, commands in file order. First line shaped `# help: Title - summary` names the group; without it the file name is used. Order functions in a file as they should read in help.
- Version is git-derived (`_dot_version`, shown by `d-version` and the `d-help` header). No version file or constant exists to bump; optional `vX.Y.Z` tags change the output.

## Verification

- Syntax-check all scripts: `bash -n dotfiles.sh install.sh commands/*.sh`
- Lint when ShellCheck is installed: `shellcheck dotfiles.sh install.sh commands/*.sh`
- Verify source/discovery without startup banner: `DOTFILES_QUIET=1 bash -c 'source ./dotfiles.sh; d-help'`
- No tracked test suite or CI config currently exists.

## Side Effects

- `install.sh` clones or updates `$DOTFILES_DIR` and modifies `~/.bashrc`; do not use it as routine verification.
- `d-aisync` mirrors Markdown files from `$HOME` into a WSL Windows path using `rsync --delete`; never invoke casually.
- `d-ginfo` runs `git fetch`; use syntax/source checks when network-free verification is required.
