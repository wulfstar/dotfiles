#!/usr/bin/env bash

alias gs='git status --short --branch'
alias gl='git log --oneline --decorate --graph --max-count=20'
alias gd='git diff'

_dot_register "gs" "Show compact git status with branch"
_dot_register "gl" "Show recent git history as a graph"
_dot_register "gd" "Show unstaged git diff"
