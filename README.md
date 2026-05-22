# dotfiles

Useful Linux aliases and bash functions that can be sourced into any shell environment.

## Install

Bootstrap with `wget`:

```bash
wget -qO- https://raw.githubusercontent.com/wulfstar/dotfiles/main/install.sh | bash
```

Or with `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/wulfstar/dotfiles/main/install.sh | bash
```

The installer clones this repo with HTTPS into `$HOME/.dotfiles`, adds this source line to `~/.bashrc`, and leaves the repo ready for future updates:

```bash
[ -f "$HOME/.dotfiles/dotfiles.sh" ] && source "$HOME/.dotfiles/dotfiles.sh"
```

Reload your shell after install:

```bash
source ~/.bashrc
```

## Dotfiles Command

The sourced environment provides a `...` command for managing this repo:

```bash
... help
... commands
... status
... update
... remote show
... remote ssh
... push
```

When sourced by an interactive shell, the environment prints:

```text
Dotfiles loaded. Run '... help' or '... commands' for more information.
```

Set `DOTFILES_QUIET=1` before sourcing to suppress that message.

Useful subcommands:

```text
... commands       List loaded dotfiles commands with one-line descriptions
... status         Show git status for the dotfiles repo
... update         Pull latest dotfiles changes
... reload         Re-source dotfiles.sh in the current shell
... remote ssh     Switch origin from HTTPS to SSH after auth is configured
... remote https   Switch origin back to HTTPS
... remote test    Test current origin connectivity
```

## Adding Commands

Add new functions under `commands/*.sh` and register them with a short description:

```bash
...mycommand() {
  printf 'hello\n'
}

_dot_register "...mycommand" "Print a greeting"
```

Then commit and push from any sourced shell:

```bash
... add commands/mycommand.sh
... commit "Add mycommand helper"
... push
```

## Included Helpers

```text
...ff <pattern> [path]       Find files by name under a path
...ftext <pattern> [path]    Search file contents under a path
...groot                     Print the current git repository root
...ginfo                     Show git project summary
...certinfo <cert.pem>       Show certificate information
...certdates <cert.pem>      Show certificate validity dates
...tlsinfo <host> [port]     Inspect a remote TLS certificate
...randhex [bytes]           Generate random hex bytes
```

## Verify

Run the smoke test:

```bash
bash test/smoke.sh
```
