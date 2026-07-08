#!/usr/bin/env bash

# File search helpers.

d-ff() { # Find files by name under a path: d-ff <pattern> [path]
  local pattern="${1:-}" path="${2:-.}"

  [ -n "$pattern" ] || { printf 'usage: d-ff <name-pattern> [path]\n' >&2; return 1; }
  find "$path" -iname "*$pattern*" 2>/dev/null
}

d-ftext() { # Search file contents under a path: d-ftext <pattern> [path]
  local pattern="${1:-}" path="${2:-.}"

  [ -n "$pattern" ] || { printf 'usage: d-ftext <text-pattern> [path]\n' >&2; return 1; }

  if _dot_has rg; then
    rg --hidden --glob '!.git' "$pattern" "$path"
  else
    grep -RIn --exclude-dir=.git "$pattern" "$path"
  fi
}

d-aisync() {

  local src="$HOME/"
  local dest="/mnt/c/Users/root/Documents/Agent-Projects/WSL/$WSL_DISTRO_NAME/"

  mkdir -p "$dest"

  rsync -av \
    --prune-empty-dirs \
    --delete \
    --exclude='.*/' \
    --include='*/' \
    --include='*.md' \
    --include='*.MD' \
    --include='*.Md' \
    --include='*.mD' \
    --exclude='*' \
    "$src" "$dest"
}
