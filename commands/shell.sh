#!/usr/bin/env bash

# help: Shell - PATH inspection and editing
#
# Shell environment helpers. The d-path-* commands change PATH in the current
# shell only; nothing is written to startup files. Positions are the numbers
# that d-path prints.

# Split PATH into the named array, keeping empty entries.
_dot_path_get() {
  local -n _dot_out="$1"
  local rest="$PATH:"
  _dot_out=()
  while [ -n "$rest" ]; do
    _dot_out+=("${rest%%:*}")
    rest="${rest#*:}"
  done
}

_dot_path_set() {
  local IFS=:
  PATH="$*"
  hash -r
}

# _dot_path_pos <value> <max>: succeed when value is a position from 1 to max.
_dot_path_pos() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= $2 )) && return 0
  _dot_die "position must be a number from 1 to $2: $1"
}

_dot_path_show() {
  if [ -z "$1" ]; then
    printf '(empty: current directory)'
  elif [[ "$1" == "$HOME" || "$1" == "$HOME"/* ]]; then
    printf '%s' "~${1#"$HOME"}"
  else
    printf '%s' "$1"
  fi
}

# _dot_path_scan <entries-array> <notes-array>: set one note per entry. A note is
# empty, "missing", "duplicate of N" (same text) or "same directory as N"
# (different text, same directory through a symlink). N is the earlier position.
_dot_path_scan() {
  local -n _dot_in="$1" _dot_notes="$2"
  local -A seen=() seen_real=()
  local i entry key real
  _dot_notes=()
  for i in "${!_dot_in[@]}"; do
    entry="${_dot_in[i]}"
    _dot_notes[i]=''

    # Trailing slashes do not change the directory, so ignore them when comparing.
    key="$entry"
    while [[ "$key" == */ && "$key" != / ]]; do key="${key%/}"; done

    if [ -n "${seen[x$key]:-}" ]; then
      _dot_notes[i]="duplicate of ${seen[x$key]}"
      continue
    fi
    seen[x$key]=$((i + 1))

    if [ -n "$entry" ] && [ ! -d "$entry" ]; then
      _dot_notes[i]='missing'
    elif real="$(cd -P -- "${entry:-.}" 2>/dev/null && pwd)" && [ -n "$real" ]; then
      if [ -n "${seen_real[x$real]:-}" ]; then
        _dot_notes[i]="same directory as ${seen_real[x$real]}"
      else
        seen_real[x$real]=$((i + 1))
      fi
    fi
  done
}

d-path() { # Print PATH one entry per line, marking duplicates and missing directories
  local reset='' dim='' yellow='' red=''
  if [ -t 1 ]; then
    reset=$'\e[0m'
    dim=$'\e[2m'
    yellow=$'\e[33m'
    red=$'\e[31m'
  fi

  local -a parts notes
  local i color dups=0 missing=0
  _dot_path_get parts
  _dot_path_scan parts notes

  for i in "${!parts[@]}"; do
    case "${notes[i]}" in
      '')
        printf '%s%3d%s  %s\n' "$dim" "$((i + 1))" "$reset" "$(_dot_path_show "${parts[i]}")"
        continue
        ;;
      missing) color="$red"; ((missing++)) ;;
      *) color="$yellow"; ((dups++)) ;;
    esac
    printf '%s%3d%s  %s%s  <- %s%s\n' "$dim" "$((i + 1))" "$reset" "$color" \
      "$(_dot_path_show "${parts[i]}")" "${notes[i]}" "$reset"
  done

  printf '\n%d entries, %d duplicate, %d missing\n' "${#parts[@]}" "$dups" "$missing"
}

d-path-add() { # Insert a directory into PATH before a position (default: end): d-path-add <dir> [position]
  local dir="${1:-}" pos="${2:-}"
  local -a parts

  [ -n "$dir" ] && [ $# -le 2 ] || { printf 'usage: d-path-add <dir> [position]\n' >&2; return 1; }
  [[ "$dir" != *:* ]] || { _dot_die "directory must not contain ':': $dir"; return 1; }

  _dot_path_get parts
  [ -n "$pos" ] || pos=$(( ${#parts[@]} + 1 ))
  _dot_path_pos "$pos" "$(( ${#parts[@]} + 1 ))" || return 1
  pos=$((10#$pos))

  if [ -d "$dir" ]; then
    dir="$(cd -- "$dir" && pwd)"
  else
    printf 'd-path-add: warning: not a directory: %s\n' "$dir" >&2
  fi

  parts=("${parts[@]:0:pos-1}" "$dir" "${parts[@]:pos-1}")
  _dot_path_set "${parts[@]}"
  printf 'added at %d: %s\n' "$pos" "$(_dot_path_show "$dir")"
}

d-path-rm() { # Remove the PATH entry at a position: d-path-rm <position>
  local pos="${1:-}" entry
  local -a parts

  [ $# -eq 1 ] || { printf 'usage: d-path-rm <position>\n' >&2; return 1; }

  _dot_path_get parts
  _dot_path_pos "$pos" "${#parts[@]}" || return 1
  pos=$((10#$pos))

  entry="${parts[pos-1]}"
  parts=("${parts[@]:0:pos-1}" "${parts[@]:pos}")
  _dot_path_set "${parts[@]}"
  printf 'removed %d: %s\n' "$pos" "$(_dot_path_show "$entry")"
}

d-path-mv() { # Move a PATH entry so it lands at a new position: d-path-mv <from> <to>
  local from="${1:-}" to="${2:-}" entry
  local -a parts

  [ $# -eq 2 ] || { printf 'usage: d-path-mv <from> <to>\n' >&2; return 1; }

  _dot_path_get parts
  _dot_path_pos "$from" "${#parts[@]}" || return 1
  _dot_path_pos "$to" "${#parts[@]}" || return 1
  from=$((10#$from)) to=$((10#$to))

  entry="${parts[from-1]}"
  parts=("${parts[@]:0:from-1}" "${parts[@]:from}")
  parts=("${parts[@]:0:to-1}" "$entry" "${parts[@]:to-1}")
  _dot_path_set "${parts[@]}"
  printf 'moved %d -> %d: %s\n' "$from" "$to" "$(_dot_path_show "$entry")"
}

d-path-dedupe() { # Remove duplicate PATH entries, keeping the one nearest position 1
  local -a parts notes kept
  local i removed=0

  _dot_path_get parts
  _dot_path_scan parts notes

  for i in "${!parts[@]}"; do
    case "${notes[i]}" in
      'duplicate of '*|'same directory as '*)
        printf 'removed %d: %s  (%s)\n' "$((i + 1))" "$(_dot_path_show "${parts[i]}")" "${notes[i]}"
        ((removed++))
        ;;
      *) kept+=("${parts[i]}") ;;
    esac
  done

  if (( removed == 0 )); then
    printf 'no duplicates\n'
    return 0
  fi
  _dot_path_set "${kept[@]}"
  printf '\n%d removed, %d entries left\n' "$removed" "${#kept[@]}"
}
