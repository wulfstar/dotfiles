#!/usr/bin/env bash

# help: Shell - PATH inspection and managed PATH entries
#
# d-path only reads PATH. The d-mpath-* commands keep a list of "managed"
# directories in a marked block at the end of the login startup file
# (~/.profile unless ~/.bash_profile or ~/.bash_login exists), so the entries
# survive new shells, and they apply the same change to the current shell.
# Set DOTFILES_PROFILE to point them at another file, for example when testing.

_DOT_MPATH_BEGIN='# >>> dotfiles managed PATH >>>'
_DOT_MPATH_END='# <<< dotfiles managed PATH <<<'

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

# _dot_mpath_read <array>: load managed entries, each "front<TAB>dir" or "end<TAB>dir".
_dot_mpath_read() {
  local -n _dot_out="$1"
  local file line
  local re="^_dot_managed_path (front|end) '(.*)'\$"
  file="$(_dot_mpath_file)"
  _dot_out=()
  [ -r "$file" ] || return 0
  while IFS= read -r line; do
    [[ "$line" =~ $re ]] && _dot_out+=("${BASH_REMATCH[1]}"$'\t'"${BASH_REMATCH[2]}")
  done < <(awk -v b="$_DOT_MPATH_BEGIN" -v e="$_DOT_MPATH_END" \
    '$0 == b { on = 1; next } $0 == e { on = 0 } on' "$file")
}

# _dot_mpath_write [entry...]: replace the managed block with these entries, or
# remove the block when there are none. The previous file is kept as a backup.
_dot_mpath_write() {
  local file tmp entry
  file="$(_dot_mpath_file)"
  [ -e "$file" ] || touch -- "$file" || return 1
  [ -f "$file" ] && [ -w "$file" ] || { _dot_die "not a writable file: $file"; return 1; }

  if grep -Fqx -- "$_DOT_MPATH_BEGIN" "$file" && ! grep -Fqx -- "$_DOT_MPATH_END" "$file"; then
    _dot_die "managed PATH block in $file has no end marker; fix it by hand"
    return 1
  fi

  tmp="$(mktemp)" || return 1
  awk -v b="$_DOT_MPATH_BEGIN" -v e="$_DOT_MPATH_END" \
    '$0 == b { skip = 1; next } $0 == e { skip = 0; next } !skip' "$file" >"$tmp"

  # The block goes last so it runs after every other PATH change in the file.
  # It is plain sh, because ~/.profile is not always read by bash.
  if [ $# -gt 0 ]; then
    [ ! -s "$tmp" ] || [ -z "$(tail -n 1 "$tmp")" ] || printf '\n' >>"$tmp"
    {
      printf '%s\n' "$_DOT_MPATH_BEGIN"
      printf '# Written by d-mpath-add and d-mpath-remove (see d-help shell). Edits by hand are lost.\n'
      printf '_dot_managed_path() {\n'
      printf '  case ":$PATH:" in\n'
      printf '    *":$2:"*) ;;\n'
      printf '    *) if [ "$1" = front ]; then PATH="$2:$PATH"; else PATH="$PATH:$2"; fi ;;\n'
      printf '  esac\n'
      printf '}\n'
      for entry in "$@"; do
        printf "_dot_managed_path %s '%s'\n" "${entry%%$'\t'*}" "${entry#*$'\t'}"
      done
      printf 'unset -f _dot_managed_path\n'
      printf 'export PATH\n'
      printf '%s\n' "$_DOT_MPATH_END"
    } >>"$tmp"
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
