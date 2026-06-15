#!/usr/bin/env bash

# Commands for managing this dotfiles repo. These operate on $DOTFILES_DIR,
# not your current directory.

d-edit() { # Open the dotfiles repo in $EDITOR
  if [ -n "${EDITOR:-}" ]; then
    "$EDITOR" "$DOTFILES_DIR"
  elif _dot_has nano; then
    nano "$DOTFILES_DIR"
  else
    vi "$DOTFILES_DIR"
  fi
}

d-path() { # Print the dotfiles repo path
  printf '%s\n' "$DOTFILES_DIR"
}

d-status() { # Show dotfiles repo git status
  _dot_git status --short --branch
}

d-update() { # Pull latest dotfiles changes (fast-forward only)
  _dot_git pull --ff-only
}

d-add() { # Stage a dotfiles repo path: d-add <path>
  [ "$#" -gt 0 ] || _dot_die 'usage: d-add <path>'
  _dot_git add -- "$@"
}

d-commit() { # Commit staged dotfiles changes: d-commit <message>
  [ "$#" -gt 0 ] || _dot_die 'usage: d-commit <message>'
  _dot_git commit -m "$*"
}

d-push() { # Push dotfiles changes
  _dot_git push
}

d-sync() { # Pull with rebase, then push
  _dot_git pull --rebase && _dot_git push
}

d-reload() { # Re-source dotfiles.sh in the current shell
  [ -f "$DOTFILES_DIR/dotfiles.sh" ] || _dot_die "missing $DOTFILES_DIR/dotfiles.sh"
  source "$DOTFILES_DIR/dotfiles.sh"
  printf 'Reloaded %s\n' "$DOTFILES_DIR/dotfiles.sh"
}

d-bootstrap() { # Re-run install.sh
  [ -f "$DOTFILES_DIR/install.sh" ] || _dot_die "missing $DOTFILES_DIR/install.sh"
  bash "$DOTFILES_DIR/install.sh"
}
