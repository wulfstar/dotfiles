#!/usr/bin/env bash

# help: Confluence - export Confluence Cloud pages for agent reference
#
# Read-only Confluence Cloud helpers.
#
# All site-specific settings and credentials live in ~/.config/confluence/env
# (created by d-confluence-setup, mode 600). Nothing site-specific is stored here.
#
#   CONFLUENCE_SITE=<site>.atlassian.net
#   CONFLUENCE_CLOUDID=<uuid>
#   CONFLUENCE_EMAIL=<email>
#   CONFLUENCE_TOKEN=<scoped read-only API token for the Confluence app>
#
# Environment variables with the same names override the file.
#
# The token must be a scoped token created for the Confluence app. A Jira scoped
# token is rejected ("scope does not match"). Scopes: read:page:confluence,
# read:space:confluence, read:label:confluence.
#
# Rules: GET requests only (all HTTP goes through _dot_conf_get). The token is
# never passed on a command line or printed. Public command bodies run in a
# subshell so variables do not leak into the interactive shell.

_dot_conf_env_file() {
  printf '%s\n' "${CONFLUENCE_ENV_FILE:-$HOME/.config/confluence/env}"
}

_dot_conf_die() {
  printf 'confluence: %s\n' "$*" >&2
  return 1
}

_dot_conf_need() {
  local c
  for c in curl jq base64 "$@"; do
    _dot_has "$c" || { _dot_conf_die "missing '$c' (install it first)"; return 1; }
  done
}

# Parse KEY=VALUE lines. Never sources the file. Existing non-empty
# environment values win over file values.
_dot_conf_parse() {
  local file="$1" k v
  [ -r "$file" ] || return 1
  while IFS='=' read -r k v || [ -n "$k" ]; do
    v="${v%$'\r'}"
    case "$v" in \"*\") v="${v#\"}"; v="${v%\"}" ;; \'*\') v="${v#\'}"; v="${v%\'}" ;; esac
    case "$k" in
      CONFLUENCE_SITE|CONFLUENCE_CLOUDID|CONFLUENCE_EMAIL|CONFLUENCE_TOKEN)
        [ -n "${!k:-}" ] || printf -v "$k" '%s' "$v" ;;
    esac
  done < "$file"
}

_dot_conf_load() {
  local file k
  file="$(_dot_conf_env_file)"
  _dot_conf_need "$@" || return 1
  if [ -r "$file" ]; then
    _dot_conf_parse "$file"
  elif [ -z "${CONFLUENCE_TOKEN:-}" ]; then
    _dot_conf_die "no config at $file (run d-confluence-setup)"
    return 1
  fi
  for k in CONFLUENCE_SITE CONFLUENCE_CLOUDID CONFLUENCE_EMAIL CONFLUENCE_TOKEN; do
    [ -n "${!k:-}" ] || { _dot_conf_die "$k not set in $file (run d-confluence-setup)"; return 1; }
  done
}

# _dot_conf_get <api v2 path> [curl -G args...]
# The only function that talks to the Confluence API. GET only. The auth header
# is fed to curl on stdin (-K -) so the token never appears in argv.
_dot_conf_get() {
  local path="$1" auth tmp code msg
  shift
  auth="$(printf '%s:%s' "$CONFLUENCE_EMAIL" "$CONFLUENCE_TOKEN" | base64 -w0)"
  tmp="$(mktemp)" || return 1
  code="$(printf 'header = "Authorization: Basic %s"\n' "$auth" |
    curl -sS -X GET -G -K - \
      -H 'Accept: application/json' \
      -o "$tmp" -w '%{http_code}' \
      "https://api.atlassian.com/ex/confluence/$CONFLUENCE_CLOUDID/wiki/api/v2/$path" "$@")"
  auth=''
  case "$code" in
    200)
      cat "$tmp"; rm -f "$tmp"; return 0 ;;
    400)
      msg="$(jq -r '[(.errors // [])[] | (.title // .detail // empty)] | join("; ")' "$tmp" 2>/dev/null)"
      _dot_conf_die "bad request: ${msg:-HTTP 400}" ;;
    401|403)
      msg="$(jq -r '.message // empty' "$tmp" 2>/dev/null)"
      _dot_conf_die "token rejected (HTTP $code${msg:+: $msg}): expired, revoked, missing scope, or not a Confluence token. Run d-confluence-setup" ;;
    404)
      _dot_conf_die "not found or no permission (HTTP 404)" ;;
    000|'')
      _dot_conf_die "request failed (network error)" ;;
    *)
      _dot_conf_die "unexpected HTTP $code" ;;
  esac
  rm -f "$tmp"
  return 1
}

# _dot_conf_page_id <page id|page URL>: print the numeric page ID.
_dot_conf_page_id() {
  local in="$1" host
  if [[ "$in" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$in"; return 0
  fi
  if [[ "$in" =~ ^https?://([^/]+) ]]; then
    host="${BASH_REMATCH[1],,}"
    [ "$host" = "${CONFLUENCE_SITE,,}" ] ||
      { _dot_conf_die "URL is on $host but config is for $CONFLUENCE_SITE"; return 1; }
  fi
  if [[ "$in" =~ /pages/([0-9]+)([/?#]|$) ]] || [[ "$in" =~ [?\&]pageId=([0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"; return 0
  fi
  if [[ "$in" =~ /wiki/x/ ]]; then
    _dot_conf_die "short /wiki/x/ links are not supported; open it and pass the full page URL"
    return 1
  fi
  _dot_conf_die "cannot find a page ID in: $in"
  return 1
}

# Convert Confluence export_view HTML on stdin to GitHub-flavored Markdown.
# Python standard library only. Usage: python3 -I -c "$_DOT_CONF_HTML2MD" <base-url>
IFS='' read -r -d '' _DOT_CONF_HTML2MD <<'PY' || true
import re, sys
from html.parser import HTMLParser
from urllib.parse import urljoin

BASE = sys.argv[1] if len(sys.argv) > 1 else ""
VOID = {"br", "img", "hr", "meta", "link", "input", "col", "area", "base", "wbr", "source"}
SKIP = {"script", "style", "head", "title", "noscript", "button", "svg", "colgroup"}
BLOCK = {"p", "div", "section", "article", "header", "footer", "main", "nav", "aside",
         "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "pre", "blockquote",
         "table", "hr", "figure", "figcaption", "dl", "dt", "dd", "details", "summary",
         "body", "html", "form", "fieldset", "center"}


class Node:
    def __init__(self, tag, attrs, parent):
        self.tag, self.attrs, self.kids, self.parent = tag, dict(attrs), [], parent

    def cls(self):
        return (self.attrs.get("class") or "").split()


class Parser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = self.cur = Node("root", [], None)

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs, self.cur)
        self.cur.kids.append(node)
        if tag not in VOID:
            self.cur = node

    def handle_startendtag(self, tag, attrs):
        self.cur.kids.append(Node(tag, attrs, self.cur))

    def handle_endtag(self, tag):
        node = self.cur
        while node is not self.root and node.tag != tag:
            node = node.parent
        if node is not self.root:
            self.cur = node.parent

    def handle_data(self, data):
        self.cur.kids.append(data)


def raw_text(n):
    if isinstance(n, str):
        return n
    if n.tag == "br":
        return "\n"
    return "".join(raw_text(k) for k in n.kids)


def wrap(mark, s):
    core = s.strip()
    if not core:
        return s
    lead = s[: len(s) - len(s.lstrip())]
    trail = s[len(s.rstrip()):]
    return lead + mark + core + mark + trail


def url(u):
    return urljoin(BASE, u) if u else ""


def inline(nodes):
    out = []
    for n in nodes:
        if isinstance(n, str):
            out.append(re.sub(r"\s+", " ", n))
            continue
        t = n.tag
        if t in SKIP:
            continue
        if t == "br":
            out.append("\n")
        elif t in ("strong", "b"):
            out.append(wrap("**", inline(n.kids)))
        elif t in ("em", "i"):
            out.append(wrap("*", inline(n.kids)))
        elif t in ("del", "s", "strike"):
            out.append(wrap("~~", inline(n.kids)))
        elif t in ("code", "tt", "kbd", "samp"):
            code = raw_text(n).replace("\n", " ")
            fence = "``" if "`" in code else "`"
            out.append(fence + code + fence if code.strip() else code)
        elif t == "a":
            text = inline(n.kids).strip()
            href = url(n.attrs.get("href"))
            # In-page anchors (table of contents) do not survive conversion.
            if href and text and not n.attrs.get("href", "").startswith(("#", "javascript:")):
                out.append("[%s](%s)" % (text, href))
            else:
                out.append(text)
        elif t == "img":
            alt = (n.attrs.get("alt") or "").strip()
            if "emoticon" in n.cls():
                out.append(n.attrs.get("data-emoji-fallback") or alt)
            elif n.attrs.get("src"):
                out.append("![%s](%s)" % (alt, url(n.attrs["src"])))
        else:
            out.append(inline(n.kids))
    return "".join(out)


def blocks(nodes):
    out, run = [], []

    def flush():
        text = re.sub(r" *\n *", "\n", inline(run)).strip()
        if text:
            out.append(text)
        run.clear()

    for n in nodes:
        if isinstance(n, str) or n.tag not in BLOCK:
            if isinstance(n, str) or n.tag not in SKIP:
                run.append(n)
            continue
        flush()
        b = block(n)
        if b.strip():
            out.append(b)
    flush()
    return out


def render(nodes, sep="\n\n"):
    return sep.join(blocks(nodes))


def code_lang(n):
    m = re.search(r"brush:\s*([\w+#-]+)", n.attrs.get("data-syntaxhighlighter-params") or "")
    if m:
        return m.group(1)
    for node in [n] + [k for k in n.kids if not isinstance(k, str)]:
        for c in node.cls():
            if c.startswith("language-"):
                return c[9:]
    return ""


def listing(n, ordered):
    items, i = [], int(n.attrs.get("start") or 1) if ordered else 1
    tasks = "inline-task-list" in n.cls()
    for k in n.kids:
        if isinstance(k, str):
            continue
        marker = "%d." % i if ordered else "-"
        if tasks:
            marker += " [x]" if "checked" in k.cls() else " [ ]"
        body = render(k.kids if k.tag == "li" else [k], "\n")
        lines = body.split("\n")
        pad = " " * (len(marker.split(" ")[0]) + 1)
        items.append(marker + " " + lines[0] + "".join("\n" + (pad + l if l else "") for l in lines[1:]))
        i += 1
    return "\n".join(items)


def table(n):
    rows = []

    def walk(x):
        for k in x.kids:
            if isinstance(k, str):
                continue
            if k.tag == "tr":
                rows.append([c for c in k.kids if not isinstance(c, str) and c.tag in ("td", "th")])
            elif k.tag in ("thead", "tbody", "tfoot"):
                walk(k)

    walk(n)
    if not rows:
        return ""
    cells = [[render(c.kids, "\n").replace("\n", "<br>").replace("|", "\\|").strip() for c in r] for r in rows]
    width = max(len(r) for r in cells) or 1
    cells = [r + [""] * (width - len(r)) for r in cells]
    lines = ["| " + " | ".join(cells[0]) + " |", "|" + " --- |" * width]
    lines += ["| " + " | ".join(r) + " |" for r in cells[1:]]
    return "\n".join(lines)


def block(n):
    t = n.tag
    if t in ("h1", "h2", "h3", "h4", "h5", "h6"):
        text = inline(n.kids).replace("\n", " ").strip()
        return "#" * int(t[1]) + " " + text if text else ""
    if t == "pre":
        code = raw_text(n).strip("\n")
        fence = "~~~~" if "```" in code else "```"
        return fence + code_lang(n) + "\n" + code + "\n" + fence
    if t == "blockquote":
        body = render(n.kids)
        return "\n".join("> " + l if l else ">" for l in body.split("\n"))
    if t == "hr":
        return "---"
    if t in ("ul", "ol"):
        return listing(n, t == "ol")
    if t == "table":
        return table(n)
    if t in ("dt", "summary"):
        text = inline(n.kids).strip()
        return "**" + text + "**" if text else ""
    return render(n.kids)


p = Parser()
p.feed(sys.stdin.read())
p.close()
md = render(p.root.kids)
md = re.sub(r"[ \t]+\n", "\n", md)
md = re.sub(r"\n{3,}", "\n\n", md).strip()
sys.stdout.write(md + "\n")
PY

# --- Public commands ---------------------------------------------------------

d-confluence-setup() { # Create or update ~/.config/confluence/env (prompts; token hidden)
  (
    _dot_conf_need || exit 1
    file="$(_dot_conf_env_file)"
    dir="$(dirname -- "$file")"
    CONFLUENCE_SITE='' CONFLUENCE_CLOUDID='' CONFLUENCE_EMAIL='' CONFLUENCE_TOKEN=''
    if [ -r "$file" ]; then
      printf 'Existing config: %s (values shown as defaults)\n' "$file" >&2
      _dot_conf_parse "$file"
    elif declare -F _dot_jira_parse >/dev/null && _dot_jira_parse "$(_dot_jira_env_file)"; then
      # Same Atlassian site and account as Jira; the token must still differ.
      printf 'Using site and email from %s as defaults\n' "$(_dot_jira_env_file)" >&2
      CONFLUENCE_SITE="${JIRA_SITE:-}" CONFLUENCE_EMAIL="${JIRA_EMAIL:-}"
    fi
    old_token="$CONFLUENCE_TOKEN"

    old_id="${CONFLUENCE_SITE%%.*}"
    read -r -p "Atlassian site name (the part before .atlassian.net) [${old_id:-none}]: " in
    site="${in:-$old_id}"
    site="${site#https://}"; site="${site#http://}"; site="${site%%/*}"
    site="${site%%.*}"
    [[ "$site" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || { _dot_conf_die "bad site name: '$site'"; exit 1; }
    site="${site,,}.atlassian.net"
    printf 'Site: %s\n' "$site" >&2

    read -r -p "Email [${CONFLUENCE_EMAIL:-}]: " in
    email="${in:-$CONFLUENCE_EMAIL}"
    [ -n "$email" ] || { _dot_conf_die "email is required"; exit 1; }

    printf 'Token must be a scoped token for the Confluence app (a Jira token is rejected).\n' >&2
    if [ -n "$old_token" ]; then
      read -r -p "API token (visible) [keep existing]: " in
    else
      read -r -p "API token (visible): " in
    fi
    token="${in:-$old_token}"
    in=''
    token="${token//[[:space:]]/}"
    [ -n "$token" ] || { _dot_conf_die "token is required"; exit 1; }
    printf 'Token received: %d chars, ends in ...%s\n' "${#token}" "${token: -4}" >&2

    printf 'Looking up cloudId for %s...\n' "$site" >&2
    cloudid="$(curl -sS -X GET "https://$site/_edge/tenant_info" | jq -r '.cloudId // empty' 2>/dev/null)"
    [ -n "$cloudid" ] || { _dot_conf_die "could not get cloudId from https://$site/_edge/tenant_info"; exit 1; }

    printf 'Checking token...\n' >&2
    CONFLUENCE_SITE="$site" CONFLUENCE_CLOUDID="$cloudid" CONFLUENCE_EMAIL="$email" CONFLUENCE_TOKEN="$token"
    _dot_conf_get spaces --data-urlencode limit=1 >/dev/null || { _dot_conf_die "not saved"; exit 1; }
    printf 'OK: token can read Confluence on %s\n' "$site" >&2

    read -r -p "Save to $file? [y/N]: " in
    case "$in" in [yY]|[yY][eE][sS]) ;; *) printf 'not saved\n' >&2; exit 1 ;; esac

    mkdir -p -m 700 -- "$dir" || { _dot_conf_die "cannot create $dir"; exit 1; }
    chmod 700 -- "$dir"
    umask 077
    tmp="$(mktemp "$dir/.env.XXXXXX")" || { _dot_conf_die "cannot create temp file in $dir"; exit 1; }
    {
      printf 'CONFLUENCE_SITE=%s\n' "$site"
      printf 'CONFLUENCE_CLOUDID=%s\n' "$cloudid"
      printf 'CONFLUENCE_EMAIL=%s\n' "$email"
      printf 'CONFLUENCE_TOKEN=%s\n' "$token"
    } > "$tmp" && chmod 600 -- "$tmp" && mv -f -- "$tmp" "$file" ||
      { rm -f -- "$tmp"; _dot_conf_die "could not write $file"; exit 1; }
    printf 'saved %s (token hidden)\n' "$file" >&2
  )
}

d-confluence-get() { # Print a page as Markdown (default) or HTML on stdout: d-confluence-get <url|page-id> [--format md|html]
  (
    usage='usage: d-confluence-get <url|page-id> [--format md|html]'
    fmt=md pos=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --format)   fmt="${2:-}"; shift ;;
        --format=*) fmt="${1#*=}" ;;
        -h|--help)  printf '%s\n' "$usage" >&2; exit 0 ;;
        --)         shift; pos+=("$@"); break ;;
        -?*)        _dot_conf_die "unknown option: $1"; exit 1 ;;
        *)          pos+=("$1") ;;
      esac
      shift
    done
    [ "${#pos[@]}" -eq 1 ] || { printf '%s\n' "$usage" >&2; exit 1; }
    case "$fmt" in
      md)   _dot_conf_load python3 || exit 1 ;;
      html) _dot_conf_load || exit 1 ;;
      *)    _dot_conf_die "bad --format '$fmt' (use md or html)"; exit 1 ;;
    esac

    id="$(_dot_conf_page_id "${pos[0]}")" || exit 1
    page="$(_dot_conf_get "pages/$id" --data-urlencode body-format=export_view)" ||
      { _dot_conf_die "page $id: lookup failed"; exit 1; }
    title="$(jq -r '.title // "untitled"' <<<"$page")"
    version="$(jq -r '.version.number // 0' <<<"$page")"
    space_id="$(jq -r '.spaceId // empty' <<<"$page")"
    base="https://$CONFLUENCE_SITE/wiki"
    source_url="$base$(jq -r '._links.webui // empty' <<<"$page")"
    [ "$source_url" != "$base" ] || source_url="$base/pages/viewpage.action?pageId=$id"

    # Space key and labels only enrich metadata; a missing scope must not stop the export.
    space=''
    [ -z "$space_id" ] || space="$(_dot_conf_get "spaces/$space_id" 2>/dev/null | jq -r '.key // empty')"
    [ -n "$space" ] || space="${space_id:-unknown}"
    labels="$(_dot_conf_get "pages/$id/labels" --data-urlencode limit=250 2>/dev/null | jq -c '[.results[]?.name]')"
    [ -n "$labels" ] || labels='[]'

    body="$(jq -r '.body.export_view.value // empty' <<<"$page")"
    [ -n "$body" ] || printf 'confluence: warning: page %s has an empty body\n' "$id" >&2
    meta=(--arg title "$title" --arg url "$source_url" --arg id "$id" --arg space "$space"
      --argjson version "$version" --argjson labels "$labels" --arg today "$(date +%F)")
    doc="$(
      if [ "$fmt" = md ]; then
        jq -nr "${meta[@]}" --arg modified "$(jq -r '.version.createdAt // ""' <<<"$page")" '
          "---",
          "title: \($title | tojson)",
          "source: \($url | tojson)",
          "page_id: \($id | tojson)",
          "space: \($space | tojson)",
          "version: \($version)",
          "last_modified: \($modified | tojson)",
          "exported: \($today | tojson)",
          "labels: \($labels | tojson)",
          "---",
          "",
          "# \($title)",
          ""'
        printf '%s' "$body" | python3 -I -c "$_DOT_CONF_HTML2MD" "https://$CONFLUENCE_SITE/" ||
          exit 1
      else
        jq -nr "${meta[@]}" --arg base "https://$CONFLUENCE_SITE/" '
          "<!doctype html>",
          "<html><head><meta charset=\"utf-8\">",
          "<title>\($title | @html)</title>",
          "<base href=\"\($base | @html)\">",
          "<meta name=\"confluence-source\" content=\"\($url | @html)\">",
          "<meta name=\"confluence-page-id\" content=\"\($id | @html)\">",
          "<meta name=\"confluence-space\" content=\"\($space | @html)\">",
          "<meta name=\"confluence-version\" content=\"\($version)\">",
          "<meta name=\"confluence-labels\" content=\"\($labels | join(",") | @html)\">",
          "<meta name=\"exported\" content=\"\($today)\">",
          "</head><body>",
          "<h1>\($title | @html)</h1>"'
        printf '%s\n</body></html>\n' "$body"
      fi
    )" || { _dot_conf_die "page $id: conversion failed"; exit 1; }
    printf '%s\n' "$doc"
  )
}
