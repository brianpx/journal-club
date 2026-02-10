#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# journal-club static site reorg for GitHub Pages + DreamHost
# - Uses WEBROOT=docs by default (GitHub Pages supports this)
# - Preserves legacy URLs via HTML redirect stubs
# - Updates asset paths to absolute /assets/... (safer from nested pages)
# - Performs link integrity check (href/src -> file exists)
#
# Usage:
#   bash scripts/reorg-site.sh
#   WEBROOT=public bash scripts/reorg-site.sh        # if you really want public/
#   DRYRUN=1 bash scripts/reorg-site.sh              # show actions, don't change
#
# After success:
#   - In GitHub: Settings → Pages → Build and deployment → Source: Deploy from a branch
#              → Branch: main → Folder: /docs
# -----------------------------------------------------------------------------

WEBROOT="${WEBROOT:-docs}"
DRYRUN="${DRYRUN:-0}"

log() { printf "\n\033[1m%s\033[0m\n" "$*"; }
run() {
  if [[ "$DRYRUN" == "1" ]]; then
    echo "[DRYRUN] $*"
  else
    eval "$@"
  fi
}

require_clean_git() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: Not inside a git repository."
    exit 1
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: Working tree not clean. Commit/stash first."
    git status --porcelain
    exit 1
  fi
}

backup_repo() {
  local ts
  ts="$(date +%Y%m%d_%H%M%S)"
  local backup="backup_before_reorg_${ts}.tar.gz"
  log "Creating backup: ${backup}"
  # Exclude node_modules and .git to keep it small
  run "tar --exclude='./.git' --exclude='./node_modules' -czf '${backup}' ."
  echo "Backup created: ${backup}"
}

is_tracked() {
  local path="$1"
  git ls-files --error-unmatch "$path" >/dev/null 2>&1
}

git_mv_if_exists_and_tracked() {
  local src="$1"
  local dst="$2"

  if [[ -e "$src" ]] && is_tracked "$src"; then
    run "mkdir -p \"$(dirname "$dst")\""
    run "git mv \"$src\" \"$dst\""
  else
    echo "Skipping (not tracked or missing): $src"
  fi
}

# Write a redirect stub at $path pointing to $target (path is within WEBROOT)
write_redirect_stub() {
  local path="$1"
  local target="$2"
  run "cat > \"$path\" <<'HTML'
<!DOCTYPE html>
<html lang=\"en\">
<head>
  <meta charset=\"UTF-8\" />
  <meta http-equiv=\"refresh\" content=\"0; url=${target}\" />
  <link rel=\"canonical\" href=\"${target}\" />
  <title>Redirecting…</title>
  <script>window.location.replace(\"${target}\");</script>
</head>
<body>
  <p>This page has moved. <a href=\"${target}\">Click here if you are not redirected.</a></p>
</body>
</html>
HTML"
}

# Update asset links inside HTML to absolute paths so nested pages don't break.
# - css/...      -> /assets/css/...
# - js/...       -> /assets/js/...
# - img/...      -> /assets/img/...
# Also handles ./css/... variants.
rewrite_asset_paths() {
  log "Rewriting asset paths in HTML to /assets/... (safe for nested pages)"
  if [[ "$DRYRUN" == "1" ]]; then
    echo "[DRYRUN] Would rewrite paths under $WEBROOT"
    return
  fi

  # Use perl in-place edits for portability
  find "$WEBROOT" -name "*.html" -type f -print0 | while IFS= read -r -d '' f; do
    perl -0777 -i -pe '
      s/(href|src)\s*=\s*"\.\/css\//$1="\/assets\/css\//g;
      s/(href|src)\s*=\s*"css\//$1="\/assets\/css\//g;

      s/(href|src)\s*=\s*"\.\/js\//$1="\/assets\/js\//g;
      s/(href|src)\s*=\s*"js\//$1="\/assets\/js\//g;

      s/(href|src)\s*=\s*"\.\/img\//$1="\/assets\/img\//g;
      s/(href|src)\s*=\s*"img\//$1="\/assets\/img\//g;
    ' "$f"
  done
}

# Link check: parse href/src attributes and ensure local targets exist.
# - Ignores http(s), mailto, tel, javascript:, # anchors
# - For absolute /foo paths, checks $WEBROOT/foo
# - For relative paths, checks relative to HTML file directory
link_check() {
  log "Running local link check (href/src → file exists)"
  if [[ "$DRYRUN" == "1" ]]; then
    echo "[DRYRUN] Would run link check under $WEBROOT"
    return
  fi

  python3 - <<PY
import os, re, sys

WEBROOT = "${WEBROOT}"
bad = []
attr_re = re.compile(r'''(?:href|src)\s*=\s*["']([^"']+)["']''', re.IGNORECASE)

def is_ignored(u: str) -> bool:
  u = u.strip()
  if not u or u.startswith("#"):
    return True
  low = u.lower()
  return (
    low.startswith("http://") or low.startswith("https://")
    or low.startswith("mailto:") or low.startswith("tel:")
    or low.startswith("javascript:")
    or low.startswith("data:")
  )

def normalize_url(u: str) -> str:
  # strip query/hash
  u = u.split("#", 1)[0].split("?", 1)[0].strip()
  return u

for root, _, files in os.walk(WEBROOT):
  for fn in files:
    if not fn.endswith(".html"):
      continue
    path = os.path.join(root, fn)
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
      html = f.read()
    for url in attr_re.findall(html):
      url = normalize_url(url)
      if is_ignored(url):
        continue

      # skip external-looking protocol-relative URLs (//cdn...)
      if url.startswith("//"):
        continue

      if url.startswith("/"):
        # absolute-from-site-root -> check under WEBROOT
        target = os.path.join(WEBROOT, url.lstrip("/"))
      else:
        # relative to current html file
        target = os.path.normpath(os.path.join(os.path.dirname(path), url))

      # If target is a directory, accept index.html
      if os.path.isdir(target):
        target = os.path.join(target, "index.html")

      if not os.path.exists(target):
        bad.append((path, url, target))

if bad:
  print("\\nBROKEN LINKS FOUND:")
  for p, url, t in bad:
    print(f"- In: {p}\\n  url: {url}\\n  expected: {t}\\n")
  sys.exit(2)

print("Link check passed.")
PY
}

main() {
  require_clean_git
  backup_repo

  log "Preparing web root: $WEBROOT"
  run "mkdir -p \"$WEBROOT\""

  # -----------------------------------------------------------------------------
  # 1) Move tracked core site content into WEBROOT (no URL changes yet)
  # -----------------------------------------------------------------------------
  log "Moving tracked site content into $WEBROOT (git mv)"

  # Directories (only if tracked)
  git_mv_if_exists_and_tracked "css"       "$WEBROOT/css"
  git_mv_if_exists_and_tracked "js"        "$WEBROOT/js"
  git_mv_if_exists_and_tracked "img"       "$WEBROOT/img"
  git_mv_if_exists_and_tracked "downloads" "$WEBROOT/downloads"
  git_mv_if_exists_and_tracked "JC"        "$WEBROOT/JC"

  # Key root files (only if tracked)
  for f in index.html jc_guide.html jc-october-2025.html JC-2025-10-14.html JC-JAN-2026.html summary-2025.html JC-Pre-session-Sept-2025.pdf; do
    git_mv_if_exists_and_tracked "$f" "$WEBROOT/$f"
  done

  if [[ "$DRYRUN" != "1" ]]; then
    if [[ -n "$(git status --porcelain)" ]]; then
      git commit -m "chore: move site content into ${WEBROOT} web root"
    else
      echo "No tracked moves detected (maybe already moved)."
    fi
  fi

  # -----------------------------------------------------------------------------
  # 2) Build clean structure inside WEBROOT
  #    - assets/{css,js,img}
  #    - guide/index.html from jc_guide.html
  #    - sessions/YYYY/MM/index.html from legacy session pages
  #    - redirect stubs for legacy URLs
  # -----------------------------------------------------------------------------
  log "Creating clean structure under $WEBROOT"

  run "mkdir -p \"$WEBROOT/assets/css\" \"$WEBROOT/assets/js\" \"$WEBROOT/assets/img\""
  run "mkdir -p \"$WEBROOT/guide\""
  run "mkdir -p \"$WEBROOT/sessions/2025/10\" \"$WEBROOT/sessions/2026/01\""
  run "mkdir -p \"$WEBROOT/summaries/2025\""

  # Move assets into assets/
  # (We keep downloads/ as-is since it is already a semantic folder)
  if [[ -d "$WEBROOT/css" ]]; then git_mv_if_exists_and_tracked "$WEBROOT/css" "$WEBROOT/assets/css"; fi
  if [[ -d "$WEBROOT/js"  ]]; then git_mv_if_exists_and_tracked "$WEBROOT/js"  "$WEBROOT/assets/js";  fi
  if [[ -d "$WEBROOT/img" ]]; then git_mv_if_exists_and_tracked "$WEBROOT/img" "$WEBROOT/assets/img"; fi

  # Guide: move content to /guide/index.html and stub old name
  if [[ -f "$WEBROOT/jc_guide.html" ]]; then
    # Move original to guide/index.html
    run "git mv \"$WEBROOT/jc_guide.html\" \"$WEBROOT/guide/index.html\""
    # Create redirect stub at legacy path
    run "git checkout --orphan __tmp__ >/dev/null 2>&1 || true"
    run "git checkout main >/dev/null 2>&1 || true"
    write_redirect_stub "$WEBROOT/jc_guide.html" "/guide/"
    if [[ "$DRYRUN" != "1" ]]; then git add "$WEBROOT/jc_guide.html"; fi
  fi

  # Sessions: pick canonical content for Oct 2025 and create redirects
  # - If JC-2025-10-14.html exists, use it as canonical content for sessions/2025/10/
  # - Else if jc-october-2025.html exists, use that.
  oct_src=""
  if [[ -f "$WEBROOT/JC-2025-10-14.html" ]]; then oct_src="$WEBROOT/JC-2025-10-14.html"; fi
  if [[ -z "$oct_src" && -f "$WEBROOT/jc-october-2025.html" ]]; then oct_src="$WEBROOT/jc-october-2025.html"; fi

  if [[ -n "$oct_src" ]]; then
    run "git mv \"$oct_src\" \"$WEBROOT/sessions/2025/10/index.html\""
    # Redirect stubs for both legacy names (if present or desired)
    write_redirect_stub "$WEBROOT/JC-2025-10-14.html" "/sessions/2025/10/"
    write_redirect_stub "$WEBROOT/jc-october-2025.html" "/sessions/2025/10/"
    if [[ "$DRYRUN" != "1" ]]; then git add "$WEBROOT/JC-2025-10-14.html" "$WEBROOT/jc-october-2025.html"; fi
  fi

  # Jan 2026 session (if file exists)
  if [[ -f "$WEBROOT/JC-JAN-2026.html" ]]; then
    run "git mv \"$WEBROOT/JC-JAN-2026.html\" \"$WEBROOT/sessions/2026/01/index.html\""
    write_redirect_stub "$WEBROOT/JC-JAN-2026.html" "/sessions/2026/01/"
    if [[ "$DRYRUN" != "1" ]]; then git add "$WEBROOT/JC-JAN-2026.html"; fi
  fi

  # Summary page (optional): if present, move to summaries/2025 and stub
  if [[ -f "$WEBROOT/summary-2025.html" ]]; then
    run "git mv \"$WEBROOT/summary-2025.html\" \"$WEBROOT/summaries/2025/index.html\""
    write_redirect_stub "$WEBROOT/summary-2025.html" "/summaries/2025/"
    if [[ "$DRYRUN" != "1" ]]; then git add "$WEBROOT/summary-2025.html"; fi
  fi

  # Rewrite asset paths in all HTML under WEBROOT
  rewrite_asset_paths

  # Run link check
  link_check

  # Commit structure changes
  if [[ "$DRYRUN" != "1" ]]; then
    if [[ -n "$(git status --porcelain)" ]]; then
      git commit -m "refactor: organize site into sessions, guide, assets with legacy redirects"
    else
      echo "No changes to commit (already organized?)."
    fi
  fi

  log "DONE"
  echo "Next steps:"
  echo "1) GitHub: Settings → Pages → Source: main branch → Folder: /${WEBROOT}"
  echo "2) DreamHost: upload ${WEBROOT}/* to your web root"
  echo "3) Test legacy URLs and new clean URLs"
}

main "$@"