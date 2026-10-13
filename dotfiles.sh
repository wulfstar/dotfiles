#!/usr/bin/env bash

# help: Dotfiles - help and version
#
# Main entrypoint for sourced dotfiles helpers.
#
# Layout:
#   dotfiles.sh    this file: helpers, d-help, and the loader for commands/*.sh
#   commands/*.sh  topic files; each user command is one `d-` function
#
# Add a command by writing a single function in any commands/*.sh file. Put a
# `#` comment on the same line as the opening brace; it becomes the d-help text:
#
#   d-greet() { # Print a greeting
#     printf 'hello\n'
#   }
#
# Append `: d-greet <args>` to that comment to give a usage string; `d-help`
# shows it only for `d-help <group>` or `d-help <command>`.
#
# It auto-loads, tab-completes as `d-<Tab>`, and appears in `d-help`. No
# registration step.
#
# Each file is one `d-help` group, listed in file order. The first line shaped
# `# help: Title - summary` names the group; without it the file name is used.

if [ -n "${BASH_VERSION:-}" ]; then
  DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
else
  DOTFILES_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
fi

export DOTFILES_DIR

# --- Shared helpers (underscore-prefixed so they stay out of `d-<Tab>`) -------

_dot_die() {
  printf 'dotfiles: %s\n' "$*" >&2
  return 1
}

_dot_has() {
  command -v "$1" >/dev/null 2>&1
}

_dot_repo() {
  [ -d "$DOTFILES_DIR/.git" ] || _dot_die "not a git repo: $DOTFILES_DIR"
}

# Version is derived from git (tag/hash, -dirty, commit date); nothing to bump.
_dot_version() {
  local rev='' date=''
  if _dot_has git && [ -d "$DOTFILES_DIR/.git" ]; then
    rev="$(git -C "$DOTFILES_DIR" describe --tags --always --dirty 2>/dev/null)"
    date="$(git -C "$DOTFILES_DIR" log -1 --format=%cs 2>/dev/null)"
  fi
  if [ -n "$rev" ]; then
    printf '%s (%s)\n' "$rev" "$date"
  else
    printf 'unknown\n'
  fi
}

# --- Discovery ---------------------------------------------------------------

d-help() { # List d- commands by group: d-help [group|command]
  local filter="${1:-}" bold='' cyan='' reset=''
  if [ -t 1 ]; then
    bold=$'\e[1m'
    cyan=$'\e[36m'
    reset=$'\e[0m'
  fi
  [ -n "$filter" ] || printf 'Dotfiles %s\n\n' "$(_dot_version)"
  # One group per file, titled by its first `# help:` line; commands keep file
  # order. Loaded d- functions found in no file land in a final "Other" group.
  awk -v filter="$filter" -v fns="$(compgen -A function -- d- | tr '\n' ' ')" \
    -v bold="$bold" -v cyan="$cyan" -v reset="$reset" '
    function add(g, name, text,    i, n) {
      n = ++gsize[g]
      cname[g, n] = name
      cdesc[g, n] = text
      i = index(text, ": " name)
      if (i) {
        cdesc[g, n] = substr(text, 1, i - 1)
        cuse[g, n] = substr(text, i + 2)
      }
      seen[name] = 1
      if (length(name) > width) width = length(name)
    }
    function line(g, n, usage) {
      printf fmt, cname[g, n], cdesc[g, n]
      if (usage && cuse[g, n] != "") print pad cuse[g, n]
    }
    function show(g, usage,    n) {
      if (!gsize[g]) return
      if (printed++) print ""
      print bold gtitle[g] reset
      for (n = 1; n <= gsize[g]; n++) line(g, n, usage)
    }
    FNR == 1 {
      key = FILENAME
      sub(/.*\//, "", key)
      sub(/\.sh$/, "", key)
      g = ++groups
      gkey[g] = key
      gtitle[g] = key
      tagged = 0
    }
    /^# help: / && !tagged {
      gtitle[g] = substr($0, 9)
      tagged = 1
      next
    }
    /^d-[A-Za-z0-9_-]+[(][)] [{]/ {
      name = $1
      sub(/[(].*/, "", name)
      i = index($0, "{ # ")
      add(g, name, i ? substr($0, i + 4) : "")
    }
    END {
      count = split(fns, defined, " ")
      for (i = 1; i <= count; i++)
        if (!(defined[i] in seen)) {
          if (!other) {
            other = ++groups
            gkey[other] = "other"
            gtitle[other] = "Other"
          }
          add(other, defined[i], "")
        }
      if (width < 14) width = 14
      fmt = "  " cyan "%-" width "s" reset "  %s\n"
      pad = sprintf("%" (width + 4) "s", "")
      want = tolower(filter)
      if (want == "") {
        for (g = 1; g <= groups; g++) show(g, 0)
        exit 0
      }
      for (g = 1; g <= groups; g++) {
        first = tolower(gtitle[g])
        sub(/ .*/, "", first)
        if (gsize[g] && (want == tolower(gkey[g]) || want == first)) {
          show(g, 1)
          exit 0
        }
      }
      for (g = 1; g <= groups; g++)
        for (n = 1; n <= gsize[g]; n++)
          if (cname[g, n] == filter || cname[g, n] == "d-" filter) {
            line(g, n, 1)
            exit 0
          }
      exit 1
    }
  ' "$DOTFILES_DIR"/dotfiles.sh "$DOTFILES_DIR"/commands/*.sh \
    || { _dot_die "no such group or command: $filter"; return 1; }
  [ -n "$filter" ] || printf '\nRun "d-help <group>" or "d-help <command>" for usage.\n'
}

d-version() { # Show dotfiles version (git revision and commit date)
  printf 'dotfiles %s\n' "$(_dot_version)"
}

# --- Load command files ------------------------------------------------------

_dot_source_dir() {
  local file
  [ -d "$1" ] || return 0
  for file in "$1"/*.sh; do
    [ -e "$file" ] || continue
    # shellcheck disable=SC1090
    source "$file"
  done
}

_dot_source_dir "$DOTFILES_DIR/commands"
unset -f _dot_source_dir

if [[ $- == *i* ]] && [ -z "${DOTFILES_QUIET:-}" ] && [ -z "${DOTFILES_MESSAGE_SHOWN:-}" ]; then
  DOTFILES_MESSAGE_SHOWN=1
  printf "Dotfiles loaded. Type 'd-' then <Tab> to list commands, or run 'd-help'.\n"
fi
