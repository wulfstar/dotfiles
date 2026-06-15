#!/usr/bin/env bash

# Git information helpers. These operate on the current directory's repo.

d-groot() { # Print the current git repository root
  git rev-parse --show-toplevel 2>/dev/null
}

d-ginfo() { # Show branch, remotes, upstream, dirty state, and recent commits
  local root branch upstream

  root="$(d-groot)" || { printf 'Not inside a git repository.\n' >&2; return 1; }
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
