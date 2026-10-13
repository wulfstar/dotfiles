# dotfiles

Useful Linux bash helpers that can be sourced into any shell environment. Every
command is a single `d-` prefixed function, so you can discover them all with
tab completion: type `d-` then press `<Tab>`.

## Install

Bootstrap with `wget`:

```bash
bash -c 'set -euo pipefail; wget -qO- https://raw.githubusercontent.com/wulfstar/dotfiles/main/install.sh | bash'
```

Or with `curl`:

```bash
bash -c 'set -euo pipefail; curl -fsSL https://raw.githubusercontent.com/wulfstar/dotfiles/main/install.sh | bash'
```

Using `pipefail` prevents a missing or inaccessible bootstrap script from looking like a successful no-op.

The installer clones this repo with HTTPS into `$HOME/.dotfiles`, adds this source line to `~/.bashrc`, and leaves the repo ready for future updates:

```bash
[ -f "$HOME/.dotfiles/dotfiles.sh" ] && source "$HOME/.dotfiles/dotfiles.sh"
```

Reload your shell after install:

```bash
source ~/.bashrc
```

## Discovering commands

Every command starts with `d-`. Type the prefix and press `<Tab>` to list them:

```bash
d-<Tab>
```

Or run `d-help` for the same list with one-line descriptions:

```bash
d-help
```

When sourced by an interactive shell, the environment prints:

```text
Dotfiles loaded. Type 'd-' then <Tab> to list commands, or run 'd-help'.
```

Set `DOTFILES_QUIET=1` before sourcing to suppress that message.

## Version

Run `d-version` to see which revision a shell has loaded:

```text
dotfiles 6b6cd1b (2026-09-25)
```

The version comes from git (`git describe --tags --always --dirty` plus the
commit date), so there is no version number to bump. A `-dirty` suffix means the
clone has uncommitted edits. `d-help` shows the same string in its header.

Tags are optional. Tag a milestone and the output changes to
`v0.1.0-2-gabc1234` style (tag, commits since the tag, hash):

```bash
git -C "$DOTFILES_DIR" tag -a v0.1.0 -m "v0.1.0"
git -C "$DOTFILES_DIR" push origin v0.1.0
```

## Commands

Manage this dotfiles repo (these act on `$HOME/.dotfiles`):

```text
d-help            List all commands with descriptions
d-version         Show dotfiles version (git revision and commit date)
d-edit            Open the dotfiles repo in $EDITOR
d-path            Print the dotfiles repo path
d-status          Show dotfiles repo git status
d-update          Pull latest dotfiles changes (fast-forward only)
d-add <path>      Stage a dotfiles repo path
d-commit <msg>    Commit staged dotfiles changes
d-push            Push dotfiles changes
d-sync            Pull with rebase, then push
d-reload          Re-source dotfiles.sh in the current shell
d-bootstrap       Re-run install.sh
```

General helpers:

```text
d-ff <pattern> [path]       Find files by name under a path
d-ftext <pattern> [path]    Search file contents under a path
d-groot                     Print the current git repository root
d-ginfo                     Show a git project summary
d-certinfo <cert.pem>       Show certificate information
d-certdates <cert.pem>      Show certificate validity dates
d-tlsinfo <host> [port]     Inspect a remote TLS certificate
d-randhex [bytes]           Generate random hex bytes
```

## Adding a command

Write one function in any `commands/*.sh` file. Put a `#` comment on the same
line as the opening brace; that text becomes its `d-help` description:

```bash
d-greet() { # Print a greeting
  printf 'hello\n'
}
```

That is the only edit. The function loads on your next shell (or after
`d-reload`), tab-completes as `d-greet`, and appears in `d-help`. There is no
registration step and no central dispatcher to update.

Pick the topic file that fits (`commands/git.sh`, `commands/search.sh`,
`commands/crypto.sh`, `commands/manage.sh`) or create a new
`commands/<topic>.sh`. Then commit and push from any sourced shell:

```bash
d-add commands/git.sh
d-commit "Add d-greet helper"
d-push
```

## How it works

- `dotfiles.sh` sets `$DOTFILES_DIR`, defines a few `_dot_*` helper functions and
  `d-help`, then sources every `commands/*.sh` file.
- Each command is a plain bash function named `d-<name>`. Internal helpers use a
  `_dot_` prefix so they stay out of `d-<Tab>` completion.
- `d-help` lists commands dynamically with `compgen` and reads descriptions from
  the source files, so there is nothing to keep in sync.

## Verify

Run the smoke test:

```bash
bash test/smoke.sh
```
