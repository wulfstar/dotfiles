#!/usr/bin/env bash

# help: Crypto - certificates and random data
#
# OpenSSL certificate and crypto helpers.

d-certinfo() { # Show readable certificate information: d-certinfo <cert.pem>
  local cert="${1:-}"

  [ -n "$cert" ] || { printf 'usage: d-certinfo <cert.pem>\n' >&2; return 1; }
  openssl x509 -in "$cert" -noout -text
}

d-certdates() { # Show certificate validity dates: d-certdates <cert.pem>
  local cert="${1:-}"

  [ -n "$cert" ] || { printf 'usage: d-certdates <cert.pem>\n' >&2; return 1; }
  openssl x509 -in "$cert" -noout -dates
}

d-tlsinfo() { # Inspect a remote TLS certificate: d-tlsinfo <host> [port]
  local host="${1:-}" port="${2:-443}"

  [ -n "$host" ] || { printf 'usage: d-tlsinfo <host> [port]\n' >&2; return 1; }
  openssl s_client -connect "$host:$port" -servername "$host" </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates -fingerprint -sha256
}

d-randhex() { # Generate random hex bytes with openssl: d-randhex [bytes]
  local bytes="${1:-16}"

  openssl rand -hex "$bytes"
}
