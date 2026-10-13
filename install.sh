#!/usr/bin/env bash
set -euo pipefail

DOTFILES_HTTPS_REMOTE="${DOTFILES_HTTPS_REMOTE:-https://github.com/wulfstar/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
# shellcheck disable=SC2016  # literal on purpose: $HOME must expand in the user's shell, not here
DOTFILES_SOURCE_LINE='[ -f "$HOME/.dotfiles/dotfiles.sh" ] && source "$HOME/.dotfiles/dotfiles.sh"'

printf 'dotfiles installer starting...\n'

require() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'install.sh: missing required command: %s\n' "$1" >&2
    exit 1
  }
}

same_repo() {
  local origin=""

  origin="$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null || true)"
  case "$origin" in
    "$DOTFILES_HTTPS_REMOTE"|git@github.com:wulfstar/dotfiles.git)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

install_source_line() {
  local bashrc="$HOME/.bashrc"

  touch "$bashrc"
  if ! grep -Fqx "$DOTFILES_SOURCE_LINE" "$bashrc"; then
    {
      printf '\n# Source personal dotfiles helpers.\n'
      printf '%s\n' "$DOTFILES_SOURCE_LINE"
    } >>"$bashrc"
    printf 'Added dotfiles source line to %s\n' "$bashrc"
  else
    printf 'Dotfiles source line already present in %s\n' "$bashrc"
  fi
}

require bash
require git

if [ -e "$DOTFILES_DIR" ]; then
  if [ ! -d "$DOTFILES_DIR/.git" ]; then
    printf 'install.sh: %s exists but is not a git repo.\n' "$DOTFILES_DIR" >&2
    exit 1
  fi

  if ! same_repo; then
    printf 'install.sh: %s is not this dotfiles repo.\n' "$DOTFILES_DIR" >&2
    printf 'Current origin: %s\n' "$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null || true)" >&2
    exit 1
  fi

  printf 'Updating %s\n' "$DOTFILES_DIR"
  git -C "$DOTFILES_DIR" pull --ff-only
else
  printf 'Cloning %s into %s\n' "$DOTFILES_HTTPS_REMOTE" "$DOTFILES_DIR"
  git clone "$DOTFILES_HTTPS_REMOTE" "$DOTFILES_DIR"
fi

install_source_line

printf '\nInstalled version: %s (%s)\n' \
  "$(git -C "$DOTFILES_DIR" describe --tags --always --dirty 2>/dev/null || printf 'unknown')" \
  "$(git -C "$DOTFILES_DIR" log -1 --format=%cs 2>/dev/null || true)"

printf '\nInstall complete. Next steps:\n'
printf '  source ~/.bashrc\n'
printf '  d-help\n'
printf '  d-version\n'
printf '  d-status\n'
