#!/usr/bin/env bash

# Miscellaneous helpers.

d-rcat() { # Remotely cat a file contents
    [[ $# -eq 2 ]] || { echo "usage: ${FUNCNAME[0]} <user@host> <remote-file>" >&2; return 1; }

    ssh "$1" "sudo -n cat -- $(printf '%q' "$2")"
}

