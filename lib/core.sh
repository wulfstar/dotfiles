#!/usr/bin/env bash

# Shared helpers for sourced dotfiles commands.

: "${DOTFILES_DIR:=$HOME/.dotfiles}"
: "${DOTFILES_HTTPS_REMOTE:=https://github.com/wulfstar/dotfiles.git}"
: "${DOTFILES_SSH_REMOTE:=git@github.com:wulfstar/dotfiles.git}"

export DOTFILES_DIR DOTFILES_HTTPS_REMOTE DOTFILES_SSH_REMOTE

DOTFILES_COMMANDS=""

_dot_die() {
  printf '...: %s\n' "$*" >&2
  return 1
}

_dot_has() {
  command -v "$1" >/dev/null 2>&1
}

_dot_repo() {
  [ -d "$DOTFILES_DIR/.git" ] || _dot_die "not a git repo: $DOTFILES_DIR"
}

_dot_git() {
  _dot_repo || return 1
  git -C "$DOTFILES_DIR" "$@"
}

_dot_register() {
  local name="$1"
  local description="$2"

  [ -n "$name" ] || return 0
  [ -n "$description" ] || description="No description provided"

  DOTFILES_COMMANDS="${DOTFILES_COMMANDS:-}${name}|${description}"$'\n'
}

_dot_commands() {
  local line name description

  printf 'Available dotfiles commands:\n\n'
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    name="${line%%|*}"
    description="${line#*|}"
    printf '  %-14s %s\n' "$name" "$description"
  done < <(printf '%s' "${DOTFILES_COMMANDS:-}" | sort -u)
}

_dot_source_line() {
  printf '%s\n' '[ -f "$HOME/.dotfiles/dotfiles.sh" ] && source "$HOME/.dotfiles/dotfiles.sh"'
}

_dot_register "..." "Manage dotfiles install, updates, remotes, and command discovery"
