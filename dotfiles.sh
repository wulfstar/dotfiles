#!/usr/bin/env bash

# Main entrypoint for sourced dotfiles helpers.
#
# Layout:
#   dotfiles.sh    this file: helpers, d-help, and the loader for commands/*.sh
#   commands/*.sh  topic files; each user command is one `d-` function
#
# Add a command by writing a single function in any commands/*.sh file. Put a
# `#` comment on the same line as the opening brace; it becomes the d-help text:
#
#   d-greet() { # Print a greeting
#     printf 'hello\n'
#   }
#
# It auto-loads, tab-completes as `d-<Tab>`, and appears in `d-help`. No
# registration step.

if [ -n "${BASH_VERSION:-}" ]; then
  DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
else
  DOTFILES_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
fi

export DOTFILES_DIR

# --- Shared helpers (underscore-prefixed so they stay out of `d-<Tab>`) -------

_dot_die() {
  printf 'dotfiles: %s\n' "$*" >&2
  return 1
}

_dot_has() {
  command -v "$1" >/dev/null 2>&1
}

_dot_repo() {
  [ -d "$DOTFILES_DIR/.git" ] || _dot_die "not a git repo: $DOTFILES_DIR"
}

# --- Discovery ---------------------------------------------------------------

d-help() { # List all d- commands with descriptions
  local fn desc
  printf 'Dotfiles commands (type "d-" then <Tab> to autocomplete):\n\n'
  for fn in $(compgen -A function -- d- | sort); do
    desc="$(sed -n "s/^${fn}() { # //p" "$DOTFILES_DIR"/dotfiles.sh "$DOTFILES_DIR"/commands/*.sh 2>/dev/null | head -n1)"
    printf '  %-16s %s\n' "$fn" "${desc:-}"
  done
}

# --- Load command files ------------------------------------------------------

_dot_source_dir() {
  local file
  [ -d "$1" ] || return 0
  for file in "$1"/*.sh; do
    [ -e "$file" ] || continue
    # shellcheck disable=SC1090
    source "$file"
  done
}

_dot_source_dir "$DOTFILES_DIR/commands"
unset -f _dot_source_dir

if [[ $- == *i* ]] && [ -z "${DOTFILES_QUIET:-}" ] && [ -z "${DOTFILES_MESSAGE_SHOWN:-}" ]; then
  DOTFILES_MESSAGE_SHOWN=1
  printf "Dotfiles loaded. Type 'd-' then <Tab> to list commands, or run 'd-help'.\n"
fi
