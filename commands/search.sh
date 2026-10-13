#!/usr/bin/env bash

# help: Search - find files and text
#
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
