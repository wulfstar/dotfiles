#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

DOTFILES_QUIET=1 source "$repo_dir/dotfiles.sh"

command -v d-help >/dev/null
command -v d-edit >/dev/null
command -v d-status >/dev/null
command -v d-ff >/dev/null
command -v d-ftext >/dev/null
command -v d-ginfo >/dev/null
command -v d-groot >/dev/null
command -v d-certinfo >/dev/null
command -v d-tlsinfo >/dev/null

d-help >/dev/null
d-path >/dev/null

# d-help must list commands and their descriptions dynamically.
help_output="$(d-help)"
grep -q 'd-ff' <<<"$help_output"
grep -q 'Find files by name' <<<"$help_output"

printf 'Smoke test passed.\n'
