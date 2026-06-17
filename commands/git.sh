#!/usr/bin/env bash

# Git information helpers. These operate on the current directory's repo.

d-groot() { # Print the current git repository root
  git rev-parse --show-toplevel 2>/dev/null
}

d-ginfo() { # Git summary: branch, upstream, ahead/behind, working tree, pull/push hints
    local branch upstream upstream_full ahead behind remote_ahead remote_behind modified untracked remote_url tracking remote_ref

    local reset="\e[0m"
    local green="\e[32m"
    local yellow="\e[33m"
    local blue="\e[34m"
    local cyan="\e[36m"
    local magenta="\e[35m"
    local red="\e[31m"

    git fetch --quiet 2>/dev/null

    branch=$(git branch --show-current 2>/dev/null) || return

    upstream_full=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)

    remote_url=$(git remote get-url origin 2>/dev/null)

    if [ -n "$upstream_full" ]; then
      tracking="${green}${upstream_full}${reset}"
      remote_ref="origin/${branch}"
    else
      tracking="${red}not tracked${reset}"
      remote_ref=""
    fi

    modified=$(git status --porcelain | grep -c '^[ MARCUD]')
    untracked=$(git status --porcelain | grep -c '^??')

    echo -e "Branch: ${green}${branch}${reset}  Tracking: ${tracking}"
    echo -e "Remote: ${cyan}${remote_url:-none}${reset}"

    if [ -n "$upstream_full" ]; then
        read ahead behind < <(git rev-list --left-right --count HEAD...@{u})

        local status_color="$green"
        if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
            status_color="$red"
        elif [ "$ahead" -gt 0 ]; then
            status_color="$cyan"
        elif [ "$behind" -gt 0 ]; then
            status_color="$blue"
        fi

        echo -e "Status: ${status_color}↑${ahead} ↓${behind}${reset}  ${yellow}M:${modified}${reset}  ${magenta}U:${untracked}${reset}"

        # Pull recommendation
        if [ "$behind" -gt 0 ] && [ "$ahead" -eq 0 ] && [ "$modified" -eq 0 ] && [ "$untracked" -eq 0 ]; then
            echo -e "Pull: ${green}git pull --ff-only${reset}"
        elif [ "$behind" -gt 0 ] && [ "$ahead" -gt 0 ]; then
            echo -e "Pull: ${yellow}git pull --rebase${reset}"
        elif [ "$behind" -eq 0 ]; then
            echo -e "Pull: ${green}up to date${reset}"
        else
            echo -e "Pull: ${red}stash/commit required${reset}"
        fi

        # -----------------------------
        # PRO-LEVEL PUSH ANALYSIS
        # -----------------------------
        if [ -n "$remote_ref" ]; then
            read remote_ahead remote_behind < <(git rev-list --left-right --count HEAD...$remote_ref 2>/dev/null)

            if [ "$remote_behind" -gt 0 ]; then
                echo -e "Push: ${yellow}git push --force-with-lease (remote diverged)${reset}"
            elif [ "$remote_ahead" -gt 0 ]; then
                echo -e "Push: ${green}git push${reset}"
            else
                echo -e "Push: ${green}nothing to push${reset}"
            fi
        fi

    else
        echo -e "Status: no upstream  ${yellow}M:${modified}${reset}  ${magenta}U:${untracked}${reset}"
    fi

    if [ -n "$upstream_full" ] && ([ "${ahead:-0}" -gt 0 ] || [ "${behind:-0}" -gt 0 ]); then
        git log --graph --decorate --oneline HEAD...@{u}
    else
        if [ "$modified" -gt 0 ] || [ "$untracked" -gt 0 ]; then
            git status --short
        else
            echo -e "${green}Working tree clean${reset}"
        fi
    fi
}

d-update() { # Pull latest changes (fast-forward only)
  git pull --ff-only
}

d-sync() { # Pull with rebase, then push
  git pull --rebase && git push
}

d-moveseq() {
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
