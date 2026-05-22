#!/usr/bin/env bash

...() {
  local command="${1:-help}"
  shift || true

  case "$command" in
    help|-h|--help)
      cat <<'EOF'
Usage: ... <command> [args]

Commands:
  help              Show this help
  commands|list     List loaded dotfiles commands
  path              Show dotfiles repo path
  status            Show dotfiles git status
  update            Pull latest dotfiles changes with --ff-only
  edit              Open dotfiles repo in $EDITOR
  add <path>        Stage a dotfiles repo path
  commit <message>  Commit staged dotfiles changes
  push              Push dotfiles changes
  sync              Pull with rebase, then push
  reload            Re-source dotfiles.sh in the current shell
  bootstrap         Run install.sh again
  remote show       Show current origin URL
  remote https      Switch origin to HTTPS remote
  remote ssh        Switch origin to SSH remote
  remote test       Test current origin connectivity
EOF
      ;;
    commands|list)
      _dot_commands
      ;;
    path)
      printf '%s\n' "$DOTFILES_DIR"
      ;;
    status)
      _dot_git status --short --branch
      ;;
    update)
      _dot_git pull --ff-only
      ;;
    edit)
      if [ -n "${EDITOR:-}" ]; then
        "$EDITOR" "$DOTFILES_DIR"
      elif _dot_has nano; then
        nano "$DOTFILES_DIR"
      else
        vi "$DOTFILES_DIR"
      fi
      ;;
    add)
      [ "$#" -gt 0 ] || _dot_die "usage: ... add <path>"
      _dot_git add -- "$@"
      ;;
    commit)
      [ "$#" -gt 0 ] || _dot_die 'usage: ... commit "message"'
      _dot_git commit -m "$*"
      ;;
    push)
      _dot_git push
      ;;
    sync)
      _dot_git pull --rebase && _dot_git push
      ;;
    reload)
      [ -f "$DOTFILES_DIR/dotfiles.sh" ] || _dot_die "missing $DOTFILES_DIR/dotfiles.sh"
      source "$DOTFILES_DIR/dotfiles.sh"
      printf 'Reloaded %s\n' "$DOTFILES_DIR/dotfiles.sh"
      ;;
    bootstrap)
      [ -f "$DOTFILES_DIR/install.sh" ] || _dot_die "missing $DOTFILES_DIR/install.sh"
      bash "$DOTFILES_DIR/install.sh"
      ;;
    remote)
      _dot_remote "$@"
      ;;
    *)
      _dot_die "unknown command: $command"
      printf 'Run `... help` for usage.\n' >&2
      return 1
      ;;
  esac
}

_dot_remote() {
  local command="${1:-show}"

  case "$command" in
    show)
      _dot_git remote get-url origin
      ;;
    https)
      _dot_git remote set-url origin "$DOTFILES_HTTPS_REMOTE" && _dot_git remote get-url origin
      ;;
    ssh)
      _dot_git remote set-url origin "$DOTFILES_SSH_REMOTE" && _dot_git remote get-url origin
      ;;
    test)
      _dot_git ls-remote origin HEAD >/dev/null && printf 'Remote is reachable.\n'
      ;;
    *)
      _dot_die "usage: ... remote {show|https|ssh|test}"
      return 1
      ;;
  esac
}
