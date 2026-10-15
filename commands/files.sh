#!/usr/bin/env bash

# help: Files - move, sync and remote read
#
# File move, sync and remote read helpers.

d-moveseq() { # Move a file without overwriting; adds -N suffix on name clash: d-moveseq <file> <dest-dir>
    local src="$1"
    local dest_dir="$2"

    if [[ ! -f "$src" ]]; then
        echo "Error: source file '$src' does not exist" >&2
        return 1
    fi

    if [[ ! -d "$dest_dir" ]]; then
        echo "Error: destination directory '$dest_dir' does not exist" >&2
        return 1
    fi

    local filename
    filename=$(basename -- "$src")

    local name="${filename%.*}"
    local ext=""

    # Preserve extension if one exists
    if [[ "$filename" == *.* && "$filename" != .* ]]; then
        ext=".${filename##*.}"
        name="${filename%.*}"
    fi

    local target="$dest_dir/$filename"
    local seq=1

    while [[ -e "$target" ]]; do
        target="$dest_dir/${name}-${seq}${ext}"
        ((seq++))
    done

    mv -- "$src" "$target"
}

d-aisync() { # Mirror Markdown and YAML files from HOME to the Windows host (WSL; uses rsync --delete)

  local src="$HOME/"
  local dest="/mnt/c/Users/root/Documents/Agent-Projects/WSL/$WSL_DISTRO_NAME/"

  mkdir -p "$dest"

  rsync -a --info=progress2 \
    --prune-empty-dirs \
    --delete \
    --exclude='.*/' \
    --include='*/' \
    --include='*.md' \
    --include='*.MD' \
    --include='*.Md' \
    --include='*.mD' \
    --include='*.[yY][aA][mM][lL]' \
    --include='*.[yY][mM][lL]' \
    --exclude='*' \
    "$src" "$dest"
}

d-rcat() { # Cat a remote file with sudo over ssh: d-rcat <user@host> <remote-file>
    [[ $# -eq 2 ]] || { echo "usage: ${FUNCNAME[0]} <user@host> <remote-file>" >&2; return 1; }

    ssh "$1" "sudo -n cat -- $(printf '%q' "$2")"
}
