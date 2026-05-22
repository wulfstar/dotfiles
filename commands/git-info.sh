#!/usr/bin/env bash

...groot() {
  git rev-parse --show-toplevel 2>/dev/null
}

...ginfo() {
  local root branch upstream

  root="$(...groot)" || { printf 'Not inside a git repository.\n' >&2; return 1; }
  branch="$(git -C "$root" branch --show-current 2>/dev/null)"
  upstream="$(git -C "$root" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"

  printf 'Root:     %s\n' "$root"
  printf 'Branch:   %s\n' "${branch:-detached HEAD}"
  printf 'Upstream: %s\n' "${upstream:-none}"
  printf '\nStatus:\n'
  git -C "$root" status --short --branch
  printf '\nRemotes:\n'
  git -C "$root" remote -v
  printf '\nRecent commits:\n'
  git -C "$root" log --oneline --decorate --max-count=8
}

_dot_register "...groot" "Print the current git repository root"
_dot_register "...ginfo" "Show branch, remotes, upstream, dirty state, and recent commits"
