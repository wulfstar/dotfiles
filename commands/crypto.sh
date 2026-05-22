#!/usr/bin/env bash

...certinfo() {
  local cert="${1:-}"

  [ -n "$cert" ] || { printf 'usage: ...certinfo <cert.pem>\n' >&2; return 1; }
  openssl x509 -in "$cert" -noout -text
}

...certdates() {
  local cert="${1:-}"

  [ -n "$cert" ] || { printf 'usage: ...certdates <cert.pem>\n' >&2; return 1; }
  openssl x509 -in "$cert" -noout -dates
}

...tlsinfo() {
  local host="${1:-}"
  local port="${2:-443}"

  [ -n "$host" ] || { printf 'usage: ...tlsinfo <host> [port]\n' >&2; return 1; }
  openssl s_client -connect "$host:$port" -servername "$host" </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates -fingerprint -sha256
}

...randhex() {
  local bytes="${1:-16}"

  openssl rand -hex "$bytes"
}

_dot_register "...certinfo" "Show readable certificate information"
_dot_register "...certdates" "Show certificate validity dates"
_dot_register "...tlsinfo" "Inspect a remote TLS certificate"
_dot_register "...randhex" "Generate random hex bytes with openssl"
