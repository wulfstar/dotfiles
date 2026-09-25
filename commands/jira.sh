#!/usr/bin/env bash

# Read-only Jira Cloud helpers.
#
# All site-specific settings and credentials live in ~/.config/jira/env
# (created by d-jira-setup, mode 600). Nothing site-specific is stored here.
#
#   JIRA_SITE=<site>.atlassian.net
#   JIRA_CLOUDID=<uuid>
#   JIRA_EMAIL=<email>
#   JIRA_TOKEN=<scoped read-only API token>
#   JIRA_PROJECT=<default project key, optional>
#   JIRA_FORMAT=<table|tsv|json|raw, optional>
#
# Environment variables with the same names override the file.
#
# Rules: GET requests only (all HTTP goes through _dot_jira_get). The token is
# never passed on a command line or printed. Public command bodies run in a
# subshell so variables do not leak into the interactive shell.

_dot_jira_env_file() {
  printf '%s\n' "${JIRA_ENV_FILE:-$HOME/.config/jira/env}"
}

_dot_jira_die() {
  printf 'jira: %s\n' "$*" >&2
  return 1
}

_dot_jira_need() {
  local c
  for c in curl jq base64 column; do
    _dot_has "$c" || { _dot_jira_die "missing '$c' (install it first)"; return 1; }
  done
}

# Parse KEY=VALUE lines. Never sources the file. Existing non-empty
# environment values win over file values.
_dot_jira_parse() {
  local file="$1" k v
  [ -r "$file" ] || return 1
  while IFS='=' read -r k v || [ -n "$k" ]; do
    v="${v%$'\r'}"
    case "$v" in \"*\") v="${v#\"}"; v="${v%\"}" ;; \'*\') v="${v#\'}"; v="${v%\'}" ;; esac
    case "$k" in
      JIRA_SITE|JIRA_CLOUDID|JIRA_EMAIL|JIRA_TOKEN|JIRA_PROJECT|JIRA_FORMAT)
        [ -n "${!k:-}" ] || printf -v "$k" '%s' "$v" ;;
    esac
  done < "$file"
}

_dot_jira_load() {
  local file
  file="$(_dot_jira_env_file)"
  _dot_jira_need || return 1
  if [ -r "$file" ]; then
    _dot_jira_parse "$file"
  elif [ -z "${JIRA_TOKEN:-}" ]; then
    _dot_jira_die "no config at $file (run d-jira-setup)"
    return 1
  fi
  local k
  for k in JIRA_SITE JIRA_CLOUDID JIRA_EMAIL JIRA_TOKEN; do
    [ -n "${!k:-}" ] || { _dot_jira_die "$k not set in $file (run d-jira-setup)"; return 1; }
  done
}

# _dot_jira_get <api path> [curl -G args...]
# The only function that talks to the Jira API. GET only. The auth header is
# fed to curl on stdin (-K -) so the token never appears in argv.
_dot_jira_get() {
  local path="$1" auth tmp code msg
  shift
  auth="$(printf '%s:%s' "$JIRA_EMAIL" "$JIRA_TOKEN" | base64 -w0)"
  tmp="$(mktemp)" || return 1
  code="$(printf 'header = "Authorization: Basic %s"\n' "$auth" |
    curl -sS -X GET -G -K - \
      -H 'Accept: application/json' \
      -o "$tmp" -w '%{http_code}' \
      "https://api.atlassian.com/ex/jira/$JIRA_CLOUDID/rest/api/3/$path" "$@")"
  auth=''
  case "$code" in
    200)
      cat "$tmp"; rm -f "$tmp"; return 0 ;;
    400)
      msg="$(jq -r '((.errorMessages // []) + ((.errors // {}) | to_entries | map("\(.key): \(.value)"))) | join("; ")' "$tmp" 2>/dev/null)"
      _dot_jira_die "bad request: ${msg:-HTTP 400}" ;;
    401|403)
      _dot_jira_die "token rejected (HTTP $code): expired, revoked, or missing scope. Run d-jira-setup" ;;
    404)
      _dot_jira_die "not found or no permission (HTTP 404)" ;;
    000|'')
      _dot_jira_die "request failed (network error)" ;;
    *)
      _dot_jira_die "unexpected HTTP $code" ;;
  esac
  rm -f "$tmp"
  return 1
}

# Parse shared options. Sets J_FORMAT J_MAX J_COMMENTS J_PROJECT J_LOOSE
# J_NOCVE J_OPEN and the J_POS array. Call only inside a subshell.
_dot_jira_args() {
  J_FORMAT="${JIRA_FORMAT:-table}"; J_MAX=50; J_COMMENTS=5
  J_PROJECT="${JIRA_PROJECT:-}"; J_LOOSE=0; J_NOCVE=0; J_OPEN=0; J_POS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --format)     J_FORMAT="${2:-}"; shift ;;
      --format=*)   J_FORMAT="${1#*=}" ;;
      -t)           J_FORMAT=tsv ;;
      -j)           J_FORMAT=json ;;
      --max)        J_MAX="${2:-}"; shift ;;
      --max=*)      J_MAX="${1#*=}" ;;
      --comments)   J_COMMENTS="${2:-}"; shift ;;
      --comments=*) J_COMMENTS="${1#*=}" ;;
      -p|--project) J_PROJECT="${2:-}"; shift ;;
      --project=*)  J_PROJECT="${1#*=}" ;;
      --loose)      J_LOOSE=1 ;;
      --no-cve)     J_NOCVE=1 ;;
      --open)       J_OPEN=1 ;;
      --)           shift; J_POS+=("$@"); break ;;
      -?*)          _dot_jira_die "unknown option: $1"; return 1 ;;
      *)            J_POS+=("$1") ;;
    esac
    shift
  done
  case "$J_FORMAT" in
    table|tsv|json|raw) ;;
    *) _dot_jira_die "bad --format '$J_FORMAT' (use table, tsv, json, or raw)"; return 1 ;;
  esac
  [[ "$J_MAX" =~ ^[1-9][0-9]*$ ]] || { _dot_jira_die "--max must be a positive number"; return 1; }
  [[ "$J_COMMENTS" =~ ^[0-9]+$ ]] || { _dot_jira_die "--comments must be a number"; return 1; }
}

# jq definitions: ADF (Atlassian Document Format) to plain text, and the
# fixed row shape used by search and dupes.
_DOT_JIRA_JQ_DEFS='
def adf:
  def kids: (.content // []) | map(adf) | join("");
  if type == "object" then
    if .type == "text" then .text
    elif .type == "hardBreak" then "\n"
    elif .type == "mention" then (.attrs.text // "")
    elif .type == "emoji" then (.attrs.text // .attrs.shortName // "")
    elif .type == "inlineCard" or .type == "blockCard" then (.attrs.url // "")
    elif .type == "listItem" then "- " + kids
    elif .type == "tableCell" or .type == "tableHeader" then kids + " | "
    elif (.type | IN("paragraph","heading","codeBlock","blockquote","bulletList",
                     "orderedList","table","tableRow","rule","panel","mediaSingle"))
      then kids + "\n"
    else kids end
  elif type == "array" then map(adf) | join("")
  elif type == "string" then .
  else "" end;
def adftext: adf | gsub("\n{3,}"; "\n\n") | sub("\\s+$"; "");
def row($site): {
  key,
  status: (.fields.status.name // null),
  created: ((.fields.created // "")[:10]),
  summary: (.fields.summary // ""),
  url: "https://\($site)/browse/\(.key)"
};
'

# _dot_jira_pages <jql> <max> <fields>: print a JSON array of search pages.
_dot_jira_pages() {
  local jql="$1" max="$2" fields="$3" token='' got=0 n page out
  out="$(mktemp)" || return 1
  while :; do
    n=$((max - got)); [ "$n" -gt 100 ] && n=100
    local args=(--data-urlencode "jql=$jql" --data-urlencode "maxResults=$n" --data-urlencode "fields=$fields")
    [ -n "$token" ] && args+=(--data-urlencode "nextPageToken=$token")
    page="$(_dot_jira_get search/jql "${args[@]}")" || { rm -f "$out"; return 1; }
    printf '%s\n' "$page" >> "$out"
    got=$((got + $(jq '.issues | length' <<<"$page")))
    token="$(jq -r 'if .isLast == true then "" else (.nextPageToken // "") end' <<<"$page")"
    [ -z "$token" ] || [ "$got" -ge "$max" ] && break
  done
  jq -s '.' "$out"
  rm -f "$out"
}

# Summarize pages: {shown, more, issues:[row]}.
_dot_jira_rows() {
  jq --arg site "$JIRA_SITE" --argjson max "$1" "$_DOT_JIRA_JQ_DEFS"'
    (map(.issues // []) | add // [] | .[:$max] | map(row($site))) as $rows
    | { shown: ($rows | length),
        more: ((last // {}) | (.isLast != true and (.nextPageToken // null) != null)),
        issues: $rows }'
}

# --- Public commands ---------------------------------------------------------

d-jira-setup() { # Create or update ~/.config/jira/env (prompts; token hidden)
  (
    _dot_jira_need || exit 1
    file="$(_dot_jira_env_file)"
    dir="$(dirname -- "$file")"
    JIRA_SITE='' JIRA_CLOUDID='' JIRA_EMAIL='' JIRA_TOKEN='' JIRA_PROJECT='' JIRA_FORMAT=''
    if [ -r "$file" ]; then
      printf 'Existing config: %s (values shown as defaults)\n' "$file" >&2
      _dot_jira_parse "$file"
    fi
    old_token="$JIRA_TOKEN"

    old_id="${JIRA_SITE%%.*}"
    read -r -p "Jira site name (the part before .atlassian.net) [${old_id:-none}]: " in
    site="${in:-$old_id}"
    site="${site#https://}"; site="${site#http://}"; site="${site%%/*}"
    site="${site%%.*}"
    [[ "$site" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || { _dot_jira_die "bad site name: '$site'"; exit 1; }
    site="${site,,}.atlassian.net"
    printf 'Site: %s\n' "$site" >&2

    read -r -p "Email [${JIRA_EMAIL:-}]: " in
    email="${in:-$JIRA_EMAIL}"
    [ -n "$email" ] || { _dot_jira_die "email is required"; exit 1; }

    read -r -p "Default project key [${JIRA_PROJECT:-none}]: " in
    project="${in:-$JIRA_PROJECT}"
    project="${project^^}"

    if [ -n "$old_token" ]; then
      read -r -p "API token (visible) [keep existing]: " in
    else
      read -r -p "API token (visible): " in
    fi
    token="${in:-$old_token}"
    in=''
    token="${token//[[:space:]]/}"
    [ -n "$token" ] || { _dot_jira_die "token is required"; exit 1; }
    printf 'Token received: %d chars, ends in ...%s\n' "${#token}" "${token: -4}" >&2

    printf 'Looking up cloudId for %s...\n' "$site" >&2
    cloudid="$(curl -sS -X GET "https://$site/_edge/tenant_info" | jq -r '.cloudId // empty' 2>/dev/null)"
    [ -n "$cloudid" ] || { _dot_jira_die "could not get cloudId from https://$site/_edge/tenant_info"; exit 1; }

    printf 'Checking token...\n' >&2
    JIRA_SITE="$site" JIRA_CLOUDID="$cloudid" JIRA_EMAIL="$email" JIRA_TOKEN="$token"
    info="$(_dot_jira_get serverInfo)" || { _dot_jira_die "not saved"; exit 1; }
    printf 'OK: %s (Jira %s)\n' "$(jq -r '.serverTitle // "?"' <<<"$info")" "$(jq -r '.version // "?"' <<<"$info")" >&2

    read -r -p "Save to $file? [y/N]: " in
    case "$in" in [yY]|[yY][eE][sS]) ;; *) printf 'not saved\n' >&2; exit 1 ;; esac

    mkdir -p -m 700 -- "$dir" || { _dot_jira_die "cannot create $dir"; exit 1; }
    chmod 700 -- "$dir"
    umask 077
    tmp="$(mktemp "$dir/.env.XXXXXX")" || { _dot_jira_die "cannot create temp file in $dir"; exit 1; }
    {
      printf 'JIRA_SITE=%s\n' "$site"
      printf 'JIRA_CLOUDID=%s\n' "$cloudid"
      printf 'JIRA_EMAIL=%s\n' "$email"
      printf 'JIRA_TOKEN=%s\n' "$token"
      if [ -n "$project" ]; then printf 'JIRA_PROJECT=%s\n' "$project"; fi
      if [ -n "$JIRA_FORMAT" ]; then printf 'JIRA_FORMAT=%s\n' "$JIRA_FORMAT"; fi
    } > "$tmp" && chmod 600 -- "$tmp" && mv -f -- "$tmp" "$file" ||
      { rm -f -- "$tmp"; _dot_jira_die "could not write $file"; exit 1; }
    printf 'saved %s (token hidden)\n' "$file" >&2
  )
}

d-jira-search() { # Search Jira by JQL: d-jira-search '<JQL>' [--max N] [--format table|tsv|json|raw]
  (
    _dot_jira_load || exit 1
    _dot_jira_args "$@" || exit 1
    [ "${#J_POS[@]}" -eq 1 ] || { printf "usage: d-jira-search '<JQL>' [--max N] [--format table|tsv|json|raw] [-t] [-j]\n" >&2; exit 1; }
    pages="$(_dot_jira_pages "${J_POS[0]}" "$J_MAX" 'summary,status,created')" || exit 1
    if [ "$J_FORMAT" = raw ]; then
      jq 'if length == 1 then .[0] else . end' <<<"$pages"; exit
    fi
    res="$(_dot_jira_rows "$J_MAX" <<<"$pages")" || exit 1
    case "$J_FORMAT" in
      json) printf '%s\n' "$res" ;;
      tsv)  jq -r '.issues[] | [.key, .status, .created, .summary] | @tsv' <<<"$res" ;;
      table)
        jq -r '.issues[] | [.key, (.status // "-"), .created, .summary] | @tsv' <<<"$res" | column -t -s $'\t'
        jq -r '"\(.shown) issues" + (if .more then " (more available, use --max N)" else "" end)' <<<"$res" >&2 ;;
    esac
  )
}

d-jira-show() { # Show one issue: d-jira-show <KEY> [--comments N] [--format table|tsv|json|raw]
  (
    _dot_jira_load || exit 1
    _dot_jira_args "$@" || exit 1
    [ "${#J_POS[@]}" -eq 1 ] || { printf 'usage: d-jira-show <KEY> [--comments N] [--format table|tsv|json|raw] [-t] [-j]\n' >&2; exit 1; }
    key="${J_POS[0]^^}"
    [[ "$key" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]] || { _dot_jira_die "bad issue key: ${J_POS[0]}"; exit 1; }
    fields='summary,status,resolution,issuetype,priority,assignee,reporter,versions,fixVersions,components,labels,created,updated,description,comment'
    body="$(_dot_jira_get "issue/$key" --data-urlencode "fields=$fields")" || { _dot_jira_die "$key: lookup failed"; exit 1; }
    if [ "$J_FORMAT" = raw ]; then printf '%s\n' "$body"; exit; fi
    res="$(jq --arg site "$JIRA_SITE" --argjson n "$J_COMMENTS" "$_DOT_JIRA_JQ_DEFS"'
      .fields as $f
      | ($f.comment.comments // []) as $all
      | {
          key,
          summary: ($f.summary // ""),
          url: "https://\($site)/browse/\(.key)",
          type: ($f.issuetype.name // null),
          priority: ($f.priority.name // null),
          status: ($f.status.name // null),
          resolution: ($f.resolution.name // null),
          assignee: ($f.assignee.displayName // null),
          reporter: ($f.reporter.displayName // null),
          affects: [($f.versions // [])[].name],
          fix: [($f.fixVersions // [])[].name],
          components: [($f.components // [])[].name],
          labels: ($f.labels // []),
          created: ($f.created // null),
          updated: ($f.updated // null),
          description: (($f.description // "") | adftext),
          comments_total: ($f.comment.total // ($all | length)),
          comments: (if $n == 0 then [] else $all[-$n:] end
                     | map({author: (.author.displayName // null), created: (.created // null), body: (.body | adftext)}))
        }' <<<"$body")" || exit 1
    case "$J_FORMAT" in
      json) printf '%s\n' "$res" ;;
      tsv)
        jq -r '
          (to_entries[] | select(.key != "comments")
            | [.key, (.value | if type == "array" then join(", ") elif . == null then "" else tostring end)] | @tsv),
          (.comments[] | ["comment", (.created // "")[:10], (.author // ""), .body] | @tsv)' <<<"$res" ;;
      table)
        jq -r '
          def d: if . == null or . == "" or . == [] then "-" elif type == "array" then join(", ") else tostring end;
          def pad($w): tostring | . + (" " * ([$w - length, 1] | max));
          def indent($p): split("\n") | map($p + .) | join("\n");
          "\(.key)  \(.summary)",
          "URL:        \(.url)",
          "Type:       \(.type | d | pad(13))Priority:   \(.priority | d)",
          "Status:     \(.status | d | pad(13))Resolution: \(.resolution // "Unresolved")",
          "Assignee:   \(.assignee | d | pad(13))Reporter:   \(.reporter | d)",
          "Affects:    \(.affects | d)",
          "Fix:        \(.fix | d)",
          "Components: \(.components | d)",
          "Labels:     \(.labels | d)",
          "Created:    \((.created // "")[:10] | d | pad(13))Updated:    \((.updated // "")[:10] | d)",
          "",
          "Description:",
          (if .description == "" then "  -" else (.description | indent("  ")) end),
          (if (.comments | length) > 0 then
             "",
             "Comments (\(.comments | length) of \(.comments_total), newest last):",
             (.comments[] | "  [\((.created // "")[:10]) \(.author // "?")]", (.body | indent("    ")))
           else empty end)' <<<"$res" ;;
    esac
  )
}

d-jira-dupes() { # Rank possible duplicates: d-jira-dupes [-p PROJECT] "<phrase>"... [--open] [--loose] [--no-cve] [--max N] [--format F]
  (
    _dot_jira_load || exit 1
    _dot_jira_args "$@" || exit 1
    [ "${#J_POS[@]}" -ge 1 ] || { printf 'usage: d-jira-dupes [-p PROJECT] "<phrase>" ["<phrase>"...] [--open] [--loose] [--no-cve] [--max N] [--format table|tsv|json|raw] [-t] [-j]\n' >&2; exit 1; }
    [ -n "$J_PROJECT" ] || { _dot_jira_die "no project: use -p PROJECT or set JIRA_PROJECT (d-jira-setup)"; exit 1; }
    [[ "$J_PROJECT" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || { _dot_jira_die "bad project key: $J_PROJECT"; exit 1; }
    project="${J_PROJECT^^}"
    out="$(mktemp)" || exit 1
    raw="$(mktemp)" || { rm -f "$out"; exit 1; }
    trap 'rm -f "$out" "$raw"' EXIT
    for phrase in "${J_POS[@]}"; do
      esc="${phrase//\\/\\\\}"; esc="${esc//\"/\\\"}"
      if [ "$J_LOOSE" = 1 ]; then term="\"$esc\""; else term="\"\\\"$esc\\\"\""; fi
      jql="project = \"$project\" AND text ~ $term"
      [ "$J_NOCVE" = 1 ] && jql+=' AND summary !~ "CVE"'
      [ "$J_OPEN" = 1 ] && jql+=' AND statusCategory != Done'
      jql+=' ORDER BY created DESC'
      pages="$(_dot_jira_pages "$jql" "$J_MAX" 'summary,status,created')" || { _dot_jira_die "phrase \"$phrase\" failed; no results shown"; exit 1; }
      jq -c '.[]' <<<"$pages" >> "$raw"
      _dot_jira_rows "$J_MAX" <<<"$pages" | jq -c --arg p "$phrase" '. + {phrase: $p}' >> "$out" || exit 1
    done
    if [ "$J_FORMAT" = raw ]; then jq -s '.' "$raw"; exit; fi
    res="$(jq -s --arg project "$project" '
      { project: $project,
        phrases: map({phrase, shown, more}),
        issues: (map(.phrase as $ph | .issues[] | . + {ph: $ph})
                 | group_by(.key)
                 | map(.[0] + {matches: length, matched: map(.ph)} | del(.ph))
                 | sort_by(.created) | reverse
                 | sort_by(-.matches)) }' "$out")" || exit 1
    n="${#J_POS[@]}"
    case "$J_FORMAT" in
      json) printf '%s\n' "$res" ;;
      tsv)  jq -r '.issues[] | [.matches, .key, .status, .created, .summary, (.matched | join("|"))] | @tsv' <<<"$res" ;;
      table)
        jq -r --arg n "$n" '.issues[] | ["\(.matches)/\($n)", .key, (.status // "-"), .created, .summary] | @tsv' <<<"$res" | column -t -s $'\t'
        jq -r '.phrases[] | "\"\(.phrase)\": \(.shown) hits" + (if .more then " (more available, use --max N)" else "" end)' <<<"$res" >&2 ;;
    esac
  )
}
