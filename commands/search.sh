#!/usr/bin/env bash

...ff() {
  local pattern="${1:-}"
  local path="${2:-.}"

  [ -n "$pattern" ] || { printf 'usage: ...ff <name-pattern> [path]\n' >&2; return 1; }
  find "$path" -iname "*$pattern*" 2>/dev/null
}

...ftext() {
  local pattern="${1:-}"
  local path="${2:-.}"

  [ -n "$pattern" ] || { printf 'usage: ...ftext <text-pattern> [path]\n' >&2; return 1; }

  if _dot_has rg; then
    rg --hidden --glob '!.git' "$pattern" "$path"
  else
    grep -RIn --exclude-dir=.git "$pattern" "$path"
  fi
}

_dot_register "...ff" "Find files by name under a path"
_dot_register "...ftext" "Search file contents under a path"
