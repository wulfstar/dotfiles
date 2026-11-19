#!/usr/bin/env bash

# help: Shell - PATH inspection, managed PATH entries and managed sourced files
#
# d-path only reads PATH. The d-mpath-* commands keep a list of "managed"
# directories in a marked block at the end of the login startup file
# (~/.profile unless ~/.bash_profile or ~/.bash_login exists), so the entries
# survive new shells, and they apply the same change to the current shell.
# Set DOTFILES_PROFILE to point them at another file, for example when testing.
#
# The d-msource-* commands keep a list of files to source in a marked block at
# the end of ~/.bashrc, so every interactive shell loads them. A file that is
# missing or unreadable at shell start is skipped quietly. Set DOTFILES_RC to
# point them at another file, for example when testing.

_DOT_MPATH_BEGIN='# >>> dotfiles managed PATH >>>'
_DOT_MPATH_END='# <<< dotfiles managed PATH <<<'
_DOT_MSOURCE_BEGIN='# >>> dotfiles managed source >>>'
_DOT_MSOURCE_END='# <<< dotfiles managed source <<<'

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

# Print the directory without trailing slashes, which do not change its meaning.
_dot_path_key() {
  local key="$1"
  while [[ "$key" == */ && "$key" != / ]]; do key="${key%/}"; done
  printf '%s' "$key"
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
    key="$(_dot_path_key "$entry")"

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

# Print the startup file that holds the managed block: the one a bash login
# shell reads.
_dot_mpath_file() {
  local file
  if [ -n "${DOTFILES_PROFILE:-}" ]; then
    printf '%s' "$DOTFILES_PROFILE"
    return 0
  fi
  for file in "$HOME/.bash_profile" "$HOME/.bash_login"; do
    [ -f "$file" ] && { printf '%s' "$file"; return 0; }
  done
  printf '%s' "$HOME/.profile"
}

# _dot_block_lines <file> <begin> <end>: print the lines between the markers.
_dot_block_lines() {
  [ -r "$1" ] || return 0
  awk -v b="$2" -v e="$3" '$0 == b { on = 1; next } $0 == e { on = 0 } on' "$1"
}

# _dot_block_write <file> <begin> <end> <label> [body-line...]: replace the
# marked block in file with the body lines, or remove the block when there are
# none. The block goes last in the file. The previous file is kept as
# <file>.dotfiles.bak.
_dot_block_write() {
  local file="$1" begin="$2" end="$3" label="$4" tmp
  shift 4
  [ -e "$file" ] || touch -- "$file" || return 1
  [ -f "$file" ] && [ -w "$file" ] || { _dot_die "not a writable file: $file"; return 1; }

  if grep -Fqx -- "$begin" "$file" && ! grep -Fqx -- "$end" "$file"; then
    _dot_die "$label block in $file has no end marker; fix it by hand"
    return 1
  fi

  tmp="$(mktemp)" || return 1
  awk -v b="$begin" -v e="$end" \
    '$0 == b { skip = 1; next } $0 == e { skip = 0; next } !skip' "$file" >"$tmp"

  if [ $# -gt 0 ]; then
    [ ! -s "$tmp" ] || [ -z "$(tail -n 1 "$tmp")" ] || printf '\n' >>"$tmp"
    printf '%s\n' "$begin" "$@" "$end" >>"$tmp"
  fi

  # Write through the existing file so a symlinked startup file stays a symlink.
  if cp -p -- "$file" "$file.dotfiles.bak" && cat -- "$tmp" >"$file"; then
    rm -f -- "$tmp"
  else
    rm -f -- "$tmp"
    _dot_die "could not update $file"
    return 1
  fi
}

# _dot_mpath_read <array>: load managed entries, each "front<TAB>dir" or "end<TAB>dir".
_dot_mpath_read() {
  local -n _dot_out="$1"
  local line
  local re="^_dot_managed_path (front|end) '(.*)'\$"
  _dot_out=()
  while IFS= read -r line; do
    [[ "$line" =~ $re ]] && _dot_out+=("${BASH_REMATCH[1]}"$'\t'"${BASH_REMATCH[2]}")
  done < <(_dot_block_lines "$(_dot_mpath_file)" "$_DOT_MPATH_BEGIN" "$_DOT_MPATH_END")
}

# _dot_mpath_write [entry...]: replace the managed block with these entries, or
# remove the block when there are none.
_dot_mpath_write() {
  local entry
  local -a body=()
  # The block goes last so it runs after every other PATH change in the file.
  # It is plain sh, because ~/.profile is not always read by bash.
  if [ $# -gt 0 ]; then
    body=(
      '# Written by d-mpath-add and d-mpath-remove (see d-help shell). Edits by hand are lost.'
      '_dot_managed_path() {'
      '  case ":$PATH:" in'
      '    *":$2:"*) ;;'
      '    *) if [ "$1" = front ]; then PATH="$2:$PATH"; else PATH="$PATH:$2"; fi ;;'
      '  esac'
      '}'
    )
    for entry in "$@"; do
      body+=("_dot_managed_path ${entry%%$'\t'*} '${entry#*$'\t'}'")
    done
    body+=('unset -f _dot_managed_path' 'export PATH')
  fi
  _dot_block_write "$(_dot_mpath_file)" "$_DOT_MPATH_BEGIN" "$_DOT_MPATH_END" "managed PATH" "${body[@]}"
}

# Print the interactive startup file that holds the managed source block.
_dot_msource_file() {
  printf '%s' "${DOTFILES_RC:-$HOME/.bashrc}"
}

# _dot_msource_read <array>: load managed sourced files.
_dot_msource_read() {
  local -n _dot_out="$1"
  local line
  local re="^_dot_managed_source '(.*)'\$"
  _dot_out=()
  while IFS= read -r line; do
    [[ "$line" =~ $re ]] && _dot_out+=("${BASH_REMATCH[1]}")
  done < <(_dot_block_lines "$(_dot_msource_file)" "$_DOT_MSOURCE_BEGIN" "$_DOT_MSOURCE_END")
}

# _dot_msource_write [file...]: replace the managed source block with these
# files, or remove the block when there are none. A missing or unreadable file
# is skipped quietly at shell start.
_dot_msource_write() {
  local entry
  local -a body=()
  if [ $# -gt 0 ]; then
    body=(
      '# Written by d-msource-add and d-msource-remove (see d-help shell). Edits by hand are lost.'
      '_dot_managed_source() { [ -f "$1" ] && [ -r "$1" ] && . "$1"; }'
    )
    for entry in "$@"; do
      body+=("_dot_managed_source '$entry'")
    done
    body+=('unset -f _dot_managed_source')
  fi
  _dot_block_write "$(_dot_msource_file)" "$_DOT_MSOURCE_BEGIN" "$_DOT_MSOURCE_END" "managed source" "${body[@]}"
}

# _dot_path_origins <entries-array> <origins-array> [unmanaged]: for each entry,
# find the startup file and line that adds it. Empty when no startup file
# mentions it. With "unmanaged", the managed block does not count as a source.
_dot_path_origins() {
  local -n _dot_in="$1" _dot_org="$2"
  local -a files=() user=() managed=()
  local -A srcdir=()
  local file line target n i key rest idx where needles='' nvm="${NVM_DIR:-$HOME/.nvm}"
  local re='(^|[[:space:];&])(source|\\?\.)[[:space:]]+"?([^"[:space:];]+)'
  _dot_org=()

  # Startup order, so the first match is the place that adds the entry.
  user=("$(_dot_mpath_file)" "$HOME/.bashrc")
  for file in /etc/environment /etc/profile /etc/profile.d/*.sh /etc/bash.bashrc "${user[@]}"; do
    [ -f "$file" ] && [ -r "$file" ] && files+=("$file")
  done

  # Follow scripts under HOME that the user files source. Such a script often
  # adds its own directory, so remember which line sourced it.
  for file in "${user[@]}"; do
    [ -r "$file" ] || continue
    n=0
    while IFS= read -r line; do
      ((n++))
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ "$line" =~ $re ]] || continue
      target="${BASH_REMATCH[3]}"
      target="${target//\$HOME/$HOME}"
      target="${target//\$\{HOME\}/$HOME}"
      [[ "$target" == "~/"* ]] && target="$HOME/${target#"~/"}"
      [[ "$target" == "$HOME"/* && -f "$target" && -r "$target" ]] || continue
      [ "$target" = "$HOME/.bashrc" ] && continue
      files+=("$target")
      [ -n "${srcdir[x${target%/*}]:-}" ] || srcdir[x${target%/*}]="$file:$n"
    done <"$file"
  done

  for i in "${!_dot_in[@]}"; do
    key="$(_dot_path_key "${_dot_in[i]}")"
    [ -n "$key" ] || continue
    needles+="$i"$'\t'"b"$'\t'"$key"$'\n'
    if [[ "$key" == "$HOME" || "$key" == "$HOME"/* ]]; then
      rest="${key#"$HOME"}"
      needles+="$i"$'\t'"b"$'\t'"\$HOME$rest"$'\n'
      needles+="$i"$'\t'"b"$'\t'"\${HOME}$rest"$'\n'
      needles+="$i"$'\t'"b"$'\t'"~$rest"$'\n'
    fi
    # nvm builds its entry from the active node version, so look for its loader.
    [[ "$key" == "$nvm"/* ]] && needles+="$i"$'\t'"r"$'\t'"nvm.sh"$'\n'
  done

  if (( ${#files[@]} )); then
    while IFS=$'\t' read -r idx where; do
      _dot_org[idx]="$where"
    done < <(awk -v b="$_DOT_MPATH_BEGIN" -v e="$_DOT_MPATH_END" '
      function pathchar(c) { return c ~ "[A-Za-z0-9_.~$}{/-]" }
      # Match s in line as a whole path, not as part of a longer one.
      function hit(line, s, m,    p, off, a, b, c) {
        off = 0
        while ((p = index(substr(line, off + 1), s)) > 0) {
          p += off
          if (m == "r") return 1
          a = p > 1 ? substr(line, p - 1, 1) : ""
          b = substr(line, p + length(s), 1)
          c = substr(line, p + length(s) + 1, 1)
          if ((a == "" || !pathchar(a)) &&
              (b == "" || !pathchar(b) || (b == "/" && (c == "" || !pathchar(c)))))
            return 1
          off = p
        }
        return 0
      }
      phase == 1 {
        split($0, f, "\t")
        n++
        idx[n] = f[1]
        mode[n] = f[2]
        needle[n] = f[3]
        next
      }
      $0 == b { block = 1 }
      $0 == e { block = 0 }
      block || /^[ \t]*#/ { next }
      {
        haspath = index($0, "PATH") > 0
        for (k = 1; k <= n; k++) {
          i = idx[k]
          if (i in best) continue
          if (!haspath && (i in any)) continue
          if (hit($0, needle[k], mode[k])) {
            if (haspath) best[i] = FILENAME ":" FNR
            else any[i] = FILENAME ":" FNR
          }
        }
      }
      END {
        for (i in best) print i "\t" best[i]
        for (i in any) if (!(i in best)) print i "\t" any[i]
      }
    ' phase=1 <(printf '%s' "$needles") phase=2 "${files[@]}")
  fi

  [ "${3:-}" = unmanaged ] || _dot_mpath_read managed
  for i in "${!_dot_in[@]}"; do
    key="$(_dot_path_key "${_dot_in[i]}")"
    [ -n "$key" ] || continue
    for line in "${managed[@]}"; do
      [ "${line#*$'\t'}" = "$key" ] && _dot_org[i]="managed ($(_dot_path_show "$(_dot_mpath_file)"))"
    done
    [ -n "${_dot_org[i]:-}" ] && continue
    if [ -n "${srcdir[x$key]:-}" ]; then
      _dot_org[i]="${srcdir[x$key]}"
    elif [ -n "${WSL_DISTRO_NAME:-}" ] && [[ "$key" == /usr/lib/wsl/* || "$key" == /mnt/* ]]; then
      _dot_org[i]='(WSL)'
    fi
  done
}

d-path() { # Print PATH one entry per line with where each is set, marking duplicates and missing directories
  local reset='' dim='' yellow='' red=''
  if [ -t 1 ]; then
    reset=$'\e[0m'
    dim=$'\e[2m'
    yellow=$'\e[33m'
    red=$'\e[31m'
  fi

  local -a parts notes origins shown
  local i color note origin width=0 dups=0 missing=0 inherited=0
  _dot_path_get parts
  _dot_path_scan parts notes
  _dot_path_origins parts origins

  for i in "${!parts[@]}"; do
    shown[i]="$(_dot_path_show "${parts[i]}")"
    (( ${#shown[i]} > width )) && width=${#shown[i]}
  done

  for i in "${!parts[@]}"; do
    color='' note=''
    case "${notes[i]}" in
      '') ;;
      missing) color="$red"; ((missing++)); note="  <- ${notes[i]}" ;;
      *) color="$yellow"; ((dups++)); note="  <- ${notes[i]}" ;;
    esac
    origin="${origins[i]:-}"
    if [ -z "$origin" ] && [ -n "${parts[i]}" ]; then
      origin='(inherited)'
      ((inherited++))
    fi
    printf '%s%3d%s  %s%-*s%s  %s%s%s%s%s%s\n' "$dim" "$((i + 1))" "$reset" \
      "$color" "$width" "${shown[i]}" "$reset" \
      "$dim" "$(_dot_path_show "$origin")" "$reset" "$color" "$note" "$reset"
  done

  printf '\n%d entries, %d duplicate, %d missing\n' "${#parts[@]}" "$dups" "$missing"
  (( inherited == 0 )) || printf '(inherited): in no startup file; it came from the program that started this shell\n'
  printf 'To add a permanent entry run d-mpath-add <dir>; to change another entry, edit the file shown.\n'
}

d-mpath-list() { # List the managed PATH directories saved in the login startup file
  local -a entries
  local i dir note
  _dot_mpath_read entries

  if (( ${#entries[@]} == 0 )); then
    printf 'no managed PATH entries in %s (add one with d-mpath-add <dir>)\n' "$(_dot_path_show "$(_dot_mpath_file)")"
    return 0
  fi

  printf 'Managed PATH entries in %s:\n\n' "$(_dot_path_show "$(_dot_mpath_file)")"
  for i in "${!entries[@]}"; do
    dir="${entries[i]#*$'\t'}"
    note=''
    [ -d "$dir" ] || note='  <- missing'
    printf '%3d  %-5s  %s%s\n' "$((i + 1))" "${entries[i]%%$'\t'*}" "$(_dot_path_show "$dir")" "$note"
  done
}

d-mpath-add() { # Add a directory to PATH permanently, at the front (default) or end: d-mpath-add <dir> [front|end]
  local dir="${1:-}" where="${2:-front}" i found=-1 present=0 moved=0 saved=1
  local -a entries parts kept

  [ -n "$dir" ] && [ $# -le 2 ] || { printf 'usage: d-mpath-add <dir> [front|end]\n' >&2; return 1; }
  case "$where" in
    front|end) ;;
    *) printf 'usage: d-mpath-add <dir> [front|end]\n' >&2; return 1 ;;
  esac

  if [ -d "$dir" ]; then
    dir="$(cd -- "$dir" && pwd)"
  elif [[ "$dir" == /* ]]; then
    dir="$(_dot_path_key "$dir")"
    printf 'd-mpath-add: warning: not a directory: %s\n' "$dir" >&2
  else
    _dot_die "not a directory (use an absolute path for one that does not exist yet): $dir"
    return 1
  fi
  if [[ "$dir" == *:* || "$dir" == *\'* || "$dir" == *$'\n'* ]]; then
    _dot_die "directory must not contain ':', a single quote or a newline: $dir"
    return 1
  fi

  _dot_mpath_read entries
  for i in "${!entries[@]}"; do
    [ "${entries[i]#*$'\t'}" = "$dir" ] && found=$i
  done
  if (( found < 0 )); then
    entries+=("$where"$'\t'"$dir")
  elif [ "${entries[found]%%$'\t'*}" = "$where" ]; then
    saved=0
  else
    entries[found]="$where"$'\t'"$dir"
    moved=1
  fi
  if (( saved )); then
    _dot_mpath_write "${entries[@]}" || return 1
  fi

  # Mirror what the block does in a new shell: add the directory unless
  # something else already put it in PATH. A managed entry that changes side
  # is taken out first so it lands on the new side.
  _dot_path_get parts
  for i in "${!parts[@]}"; do
    if [ "$(_dot_path_key "${parts[i]}")" = "$dir" ] && [ -n "${parts[i]}" ]; then
      (( moved )) && continue
      present=1
    fi
    kept+=("${parts[i]}")
  done
  if (( present == 0 )); then
    if [ "$where" = front ]; then kept=("$dir" "${kept[@]}"); else kept+=("$dir"); fi
  fi
  _dot_path_set "${kept[@]}"

  if (( saved )); then
    printf 'managed (%s): %s\n' "$where" "$(_dot_path_show "$dir")"
    printf 'saved to %s; applied to this shell\n' "$(_dot_path_show "$(_dot_mpath_file)")"
    (( present == 0 || found >= 0 )) || printf 'note: already in PATH from another source, so its position does not change\n'
  else
    printf 'already managed (%s): %s\n' "$where" "$(_dot_path_show "$dir")"
  fi
}

d-mpath-here() { # Add the current directory to PATH permanently, at the front (default) or end: d-mpath-here [front|end]
  case "$#:${1:-}" in
    0:|1:front|1:end) ;;
    *) printf 'usage: d-mpath-here [front|end]\n' >&2; return 1 ;;
  esac
  d-mpath-add "$PWD" "$@"
}

d-mpath-remove() { # Remove a managed PATH directory by its d-mpath-list number or its path: d-mpath-remove <number|dir>
  local arg="${1:-}" i found=-1 dir
  local -a entries parts kept one origin

  [ $# -eq 1 ] && [ -n "$arg" ] || { printf 'usage: d-mpath-remove <number|dir>\n' >&2; return 1; }

  _dot_mpath_read entries
  (( ${#entries[@]} )) || { _dot_die "no managed PATH entries"; return 1; }

  if [[ "$arg" =~ ^[0-9]+$ ]]; then
    _dot_path_pos "$arg" "${#entries[@]}" || return 1
    found=$((10#$arg - 1))
  else
    if [ -d "$arg" ]; then arg="$(cd -- "$arg" && pwd)"; else arg="$(_dot_path_key "$arg")"; fi
    for i in "${!entries[@]}"; do
      [ "${entries[i]#*$'\t'}" = "$arg" ] && found=$i
    done
    (( found >= 0 )) || { _dot_die "not a managed PATH entry: $arg"; return 1; }
  fi

  dir="${entries[found]#*$'\t'}"
  unset 'entries[found]'
  _dot_mpath_write "${entries[@]}" || return 1

  printf 'removed: %s\n' "$(_dot_path_show "$dir")"

  # A new shell keeps the directory when another startup file also sets it, so
  # leave it in this shell too.
  one=("$dir")
  _dot_path_origins one origin unmanaged
  if [ -n "${origin[0]:-}" ]; then
    printf 'updated %s; still in PATH, also set by %s\n' \
      "$(_dot_path_show "$(_dot_mpath_file)")" "$(_dot_path_show "${origin[0]}")"
    return 0
  fi

  _dot_path_get parts
  for i in "${!parts[@]}"; do
    [ -n "${parts[i]}" ] && [ "$(_dot_path_key "${parts[i]}")" = "$dir" ] && continue
    kept+=("${parts[i]}")
  done
  _dot_path_set "${kept[@]}"
  printf 'updated %s; removed from this shell\n' "$(_dot_path_show "$(_dot_mpath_file)")"
}

# Print the file as an absolute path with "." and ".." resolved in its directory.
_dot_msource_abs() {
  local file="$1" dir base
  [[ "$file" == */* ]] || file="./$file"
  dir="${file%/*}" base="${file##*/}"
  [ -n "$dir" ] || dir=/
  if [ -d "$dir" ]; then
    dir="$(cd -- "$dir" && pwd)" || return 1
  elif [[ "$dir" != /* ]]; then
    dir="$PWD/$dir"
  fi
  [ "$dir" = / ] && dir=''
  printf '%s/%s' "$dir" "$base"
}

d-msource-list() { # List the files that ~/.bashrc sources through the managed block
  local -a entries
  local i file note
  _dot_msource_read entries

  if (( ${#entries[@]} == 0 )); then
    printf 'no managed sourced files in %s (add one with d-msource-add <file>)\n' "$(_dot_path_show "$(_dot_msource_file)")"
    return 0
  fi

  printf 'Managed sourced files in %s:\n\n' "$(_dot_path_show "$(_dot_msource_file)")"
  for i in "${!entries[@]}"; do
    file="${entries[i]}"
    note=''
    if [ ! -f "$file" ]; then
      note='  <- missing'
    elif [ ! -r "$file" ]; then
      note='  <- unreadable'
    fi
    printf '%3d  %s%s\n' "$((i + 1))" "$(_dot_path_show "$file")" "$note"
  done
}

d-msource-add() { # Source a file in every new interactive shell and in this one: d-msource-add <file>
  local file="${1:-}" entry
  local -a entries

  [ $# -eq 1 ] && [ -n "$file" ] || { printf 'usage: d-msource-add <file>\n' >&2; return 1; }
  [ -d "$file" ] && { _dot_die "is a directory: $file"; return 1; }
  file="$(_dot_msource_abs "$file")" || return 1
  if [[ "$file" == *\'* || "$file" == *$'\n'* ]]; then
    _dot_die "file must not contain a single quote or a newline: $file"
    return 1
  fi
  if [ "$file" = "$(_dot_msource_abs "$(_dot_msource_file)")" ]; then
    _dot_die "refusing to make $file source itself"
    return 1
  fi

  _dot_msource_read entries
  for entry in "${entries[@]}"; do
    if [ "$entry" = "$file" ]; then
      printf 'already managed: %s\n' "$(_dot_path_show "$file")"
      return 0
    fi
  done

  entries+=("$file")
  _dot_msource_write "${entries[@]}" || return 1
  printf 'managed: %s\n' "$(_dot_path_show "$file")"

  if [ -f "$file" ] && [ -r "$file" ]; then
    # shellcheck disable=SC1090
    . "$file"
    printf 'saved to %s; sourced in this shell\n' "$(_dot_path_show "$(_dot_msource_file)")"
  else
    printf 'saved to %s; not sourced now: missing or unreadable (skipped at shell start until it exists)\n' \
      "$(_dot_path_show "$(_dot_msource_file)")"
  fi
}

d-msource-remove() { # Stop sourcing a managed file, by its d-msource-list number or its path: d-msource-remove <number|file>
  local arg="${1:-}" i found=-1 file
  local -a entries

  [ $# -eq 1 ] && [ -n "$arg" ] || { printf 'usage: d-msource-remove <number|file>\n' >&2; return 1; }

  _dot_msource_read entries
  (( ${#entries[@]} )) || { _dot_die "no managed sourced files"; return 1; }

  if [[ "$arg" =~ ^[0-9]+$ ]]; then
    _dot_path_pos "$arg" "${#entries[@]}" || return 1
    found=$((10#$arg - 1))
  else
    arg="$(_dot_msource_abs "$arg")" || return 1
    for i in "${!entries[@]}"; do
      [ "${entries[i]}" = "$arg" ] && found=$i
    done
    (( found >= 0 )) || { _dot_die "not a managed sourced file: $arg"; return 1; }
  fi

  file="${entries[found]}"
  unset 'entries[found]'
  _dot_msource_write "${entries[@]}" || return 1

  printf 'removed: %s\n' "$(_dot_path_show "$file")"
  printf 'updated %s; what it defined stays in this shell until you open a new one\n' \
    "$(_dot_path_show "$(_dot_msource_file)")"
}
