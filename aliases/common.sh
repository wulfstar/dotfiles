#!/usr/bin/env bash

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

_dot_register "ll" "List files with details, including hidden files"
_dot_register "la" "List hidden and visible files"
_dot_register "l" "List files in compact columns"
