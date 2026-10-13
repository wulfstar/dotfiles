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

Or run `d-help` for the same list, grouped by topic with one-line descriptions:

```bash
d-help
```

Pass a group or command name to also see usage:

```bash
d-help jira
d-help d-ftext
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

`d-help` prints this list, grouped by command file:

```text
Dotfiles - help and version
  d-help          List d- commands by group
  d-version       Show dotfiles version (git revision and commit date)

Crypto - certificates and random data
  d-certinfo      Show readable certificate information
  d-certdates     Show certificate validity dates
  d-tlsinfo       Inspect a remote TLS certificate
  d-randhex       Generate random hex bytes with openssl

Files - move, sync and remote read
  d-moveseq       Move a file without overwriting; adds -N suffix on name clash
  d-aisync        Mirror Markdown files from HOME to the Windows host (WSL; uses rsync --delete)
  d-rcat          Cat a remote file with sudo over ssh

Git - repository info and sync
  d-groot         Print the current git repository root
  d-ginfo         Git summary: branch, upstream, ahead/behind, working tree, pull/push hints
  d-update        Pull the current repository (fast-forward only)
  d-sync          Pull the current repository with rebase, then push

Jira - read-only Jira Cloud search
  d-jira-setup    Create or update ~/.config/jira/env (prompts; token hidden)
  d-jira-search   Search Jira by JQL
  d-jira-show     Show one issue
  d-jira-dupes    Rank possible duplicates

Search - find files and text
  d-ff            Find files by name under a path
  d-ftext         Search file contents under a path

Shell - PATH inspection and editing
  d-path          Print PATH one entry per line, marking duplicates and missing directories
  d-path-add      Insert a directory into PATH before a position (default: end)
  d-path-rm       Remove the PATH entry at a position
  d-path-mv       Move a PATH entry so it lands at a new position
  d-path-dedupe   Remove duplicate PATH entries, keeping the one nearest position 1
```

Arguments are not shown in the full list. Pass a group or command name to see
them:

```text
$ d-help search
Search - find files and text
  d-ff            Find files by name under a path
                  d-ff <pattern> [path]
  d-ftext         Search file contents under a path
                  d-ftext <pattern> [path]
```

## Updating

The dotfiles are a plain git clone. Pull, then reload the shell:

```bash
git -C "$DOTFILES_DIR" pull --ff-only
source "$DOTFILES_DIR/dotfiles.sh"
d-version
```

## Adding a command

Write one function in any `commands/*.sh` file. Put a `#` comment on the same
line as the opening brace; that text becomes its `d-help` description:

```bash
d-greet() { # Print a greeting
  printf 'hello\n'
}
```

To document arguments, append `: d-greet <args>` to the comment. `d-help` shows
that usage string only for `d-help <group>` or `d-help d-greet`:

```bash
d-greet() { # Print a greeting: d-greet [name]
```

Each file is one `d-help` group, and commands appear in the order they are
written in the file. Name the group with a `# help:` line near the top of the
file; without it the file name is used:

```bash
# help: Git - repository info and sync
```

That is the only edit. The function loads on your next shell (or after
`source "$DOTFILES_DIR/dotfiles.sh"`), tab-completes as `d-greet`, and appears
in `d-help`. There is no registration step and no central dispatcher to update.

Pick the topic file that fits (`commands/crypto.sh`, `commands/files.sh`,
`commands/git.sh`, `commands/jira.sh`, `commands/search.sh`,
`commands/shell.sh`) or create a new
`commands/<topic>.sh`. Then commit and push with git:

```bash
git -C "$DOTFILES_DIR" add commands/git.sh
git -C "$DOTFILES_DIR" commit -m "Add d-greet helper"
git -C "$DOTFILES_DIR" push
```

## How it works

- `dotfiles.sh` sets `$DOTFILES_DIR`, defines a few `_dot_*` helper functions,
  `d-help` and `d-version`, then sources every `commands/*.sh` file.
- Each command is a plain bash function named `d-<name>`. Internal helpers use a
  `_dot_` prefix so they stay out of `d-<Tab>` completion.
- `d-help` reads group titles and descriptions from the source files, so there
  is nothing to keep in sync.

## Verify

There is no test suite. Check syntax and that everything loads:

```bash
bash -n dotfiles.sh install.sh commands/*.sh
DOTFILES_QUIET=1 bash -c 'source ./dotfiles.sh; d-help'
```
