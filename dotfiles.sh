#!/usr/bin/env bash

# Main entrypoint for sourced dotfiles helpers.

if [ -n "${BASH_VERSION:-}" ]; then
  DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
else
  DOTFILES_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
fi

export DOTFILES_DIR

_dot_source_file() {
  [ -f "$1" ] && source "$1"
}

_dot_source_dir() {
  local file
  [ -d "$1" ] || return 0

  for file in "$1"/*.sh; do
    [ -e "$file" ] || continue
    _dot_source_file "$file"
  done
}

_dot_source_file "$DOTFILES_DIR/lib/core.sh"
_dot_source_dir "$DOTFILES_DIR/aliases"
_dot_source_dir "$DOTFILES_DIR/commands"

if [[ $- == *i* ]] && [ -z "${DOTFILES_QUIET:-}" ] && [ -z "${DOTFILES_MESSAGE_SHOWN:-}" ]; then
  DOTFILES_MESSAGE_SHOWN=1
  printf "Dotfiles loaded. Run '... help' or '... commands' for more information.\n"
fi

unset -f _dot_source_file _dot_source_dir
