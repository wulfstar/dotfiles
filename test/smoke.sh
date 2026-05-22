#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

DOTFILES_QUIET=1 source "$repo_dir/dotfiles.sh"

command -v ... >/dev/null
command -v ...ff >/dev/null
command -v ...ftext >/dev/null
command -v ...ginfo >/dev/null
command -v ...groot >/dev/null
command -v ...certinfo >/dev/null
command -v ...tlsinfo >/dev/null

... commands >/dev/null
... path >/dev/null

printf 'Smoke test passed.\n'
