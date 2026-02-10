#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# journal-club static site reorganization
#
# Goals:
# - Prepare a clean GitHub Pages–compatible publish root (default: docs/)
# - Preserve all legacy URLs via HTML redirect stubs
# - Normalize asset paths to absolute /assets/...
# - Validate internal links before completion
#
# Usage:
#   bash scripts/reorg-site.sh
#   WEBROOT=public bash scripts/reorg-site.sh
#   DRYRUN=1 bash scripts/reorg-site.sh
#
# GitHub Pages:
#   Settings → Pages → Deploy from branch → main → /docs
# =============================================================================

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

# -----------------------------------------------------------------------------
# Safety checks (ABSOLUTELY NO MUTATIONS HERE)
# -----------------------------------------------------------------------------
require_clean_git() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "ERROR: Not inside a git repository."
    exit 1
  }

  if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: Working tree not clean. Commit or stash first."
    git status --porcelain
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# Backup (excluded from git + tar)
# -----------------------------------------------------------------------------
backup_repo() {
  local ts backup
  ts="$(date +%Y%m%d_%H%M%S)"
  backup="backup_before_reorg_${ts}.tar.gz"

  log "Creating backup: ${backup}"

  run "tar \
    --exclude='./.git' \
    --exclude='./node_modules' \
    --exclude='backup_before_reorg_*.tar.gz' \
    -czf '${backup}' ."

  echo "Backup written: ${backup} (local only)"
}

# -----------------------------------------------------------------------------
# Git helpers
# -----------------------------------------------------------------------------
is_tracked() {
  git ls-files --error-unmatch "$1" >/dev/null 2>&1
}

git_mv_if_tracked() {
  local src="$1" dst="$2"

  if [[ -e "$src" ]] && is_tracked "$src"; then
    run "mkdir -p \"$(dirname "$dst")\""
    run "git mv \"$src\" \"$dst\""
  else
    echo "Skipping (not tracked or missing): $src"
  fi
}

# -----------------------------------------------------------------------------
# Redirect stub
# -----------------------------------------------------------------------------
write_redirect_stub() {
  local path="$1" target="$2"

  run "cat > \"$path\" <<HTML
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
  <p>This page has moved.
     <a href=\"${target}\">Click here if not redirected.</a></p>
</body>
</html>
HTML"
}

# -----------------------------------------------------------------------------
# Asset path normalization
# -----------------------------------------------------------------------------
rewrite_asset_paths() {
  log "Normalizing asset paths to /assets/..."

  [[ "$DRYRUN" == "1" ]] && { echo "[DRYRUN] Skipping rewrite"; return; }

  find "$WEBROOT" -name "*.html" -type f -print0 |
  while IFS= read -r -d '' f; do
    perl -0777 -i -pe '
      s/(href|src)\s*=\s*"\.?(\/)?css\//$1="\/assets\/css\//g;
      s/(href|src)\s*=\s*"\.?(\/)?js\//$1="\/assets\/js\//g;
      s/(href|src)\s*=\s*"\.?(\/)?img\//$1="\/assets\/img\//g;
    ' "$f"
  done
}

# -----------------------------------------------------------------------------
# Link integrity check
# -----------------------------------------------------------------------------
link_check() {
  log "Running internal link check"

  [[ "$DRYRUN" == "1" ]] && { echo "[DRYRUN] Skipping link check"; return; }

  python3 - <<PY
import os, re, sys

ROOT = "${WEBROOT}"
bad = []

attr = re.compile(r'(?:href|src)=["\']([^"\']+)["\']', re.I)

def ignore(u):
    u = u.strip().lower()
    return (
        not u or u.startswith("#") or
        u.startswith(("http:", "https:", "mailto:", "tel:", "javascript:", "data:", "//"))
    )

for root, _, files in os.walk(ROOT):
    for f in files:
        if not f.endswith(".html"):
            continue
        p = os.path.join(root, f)
        html = open(p, encoding="utf-8", errors="ignore").read()
        for u in attr.findall(html):
            if ignore(u):
                continue
            u = u.split("#")[0].split("?")[0]
            tgt = os.path.join(ROOT, u.lstrip("/")) if u.startswith("/") \
                  else os.path.normpath(os.path.join(os.path.dirname(p), u))
            if os.path.isdir(tgt):
                tgt = os.path.join(tgt, "index.html")
            if not os.path.exists(tgt):
                bad.append((p, u, tgt))

if bad:
    print("BROKEN LINKS:")
    for p,u,t in bad:
        print(f"- {p}\n  {u} → {t}")
    sys.exit(2)

print("Link check passed.")
PY
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  require_clean_git
  backup_repo

  log "Preparing publish root: $WEBROOT"
  run "mkdir -p \"$WEBROOT\""

  # ---------------------------------------------------------------------------
  # Phase 1: move tracked content into WEBROOT
  # ---------------------------------------------------------------------------
  log "Phase 1: moving tracked content"

  for d in css js img downloads JC; do
    git_mv_if_tracked "$d" "$WEBROOT/$d"
  done

  for f in index.html jc_guide.html jc-october-2025.html JC-2025-10-14.html JC-JAN-2026.html summary-2025.html JC-Pre-session-Sept-2025.pdf; do
    git_mv_if_tracked "$f" "$WEBROOT/$f"
  done

  # ---------------------------------------------------------------------------
  # Phase 2: structure + redirects
  # ---------------------------------------------------------------------------
  log "Phase 2: sessions, guide, assets, redirects"

  run "mkdir -p \
    \"$WEBROOT/assets/css\" \
    \"$WEBROOT/assets/js\" \
    \"$WEBROOT/assets/img\" \
    \"$WEBROOT/guide\" \
    \"$WEBROOT/sessions/2025/10\" \
    \"$WEBROOT/sessions/2026/01\" \
    \"$WEBROOT/summaries/2025\""

  git_mv_if_tracked "$WEBROOT/css" "$WEBROOT/assets/css"
  git_mv_if_tracked "$WEBROOT/js"  "$WEBROOT/assets/js"
  git_mv_if_tracked "$WEBROOT/img" "$WEBROOT/assets/img"

  if [[ -f "$WEBROOT/jc_guide.html" ]]; then
    run "git mv \"$WEBROOT/jc_guide.html\" \"$WEBROOT/guide/index.html\""
    write_redirect_stub "$WEBROOT/jc_guide.html" "/guide/"
  fi

  if [[ -f "$WEBROOT/JC-2025-10-14.html" ]]; then
    run "git mv \"$WEBROOT/JC-2025-10-14.html\" \"$WEBROOT/sessions/2025/10/index.html\""
    write_redirect_stub "$WEBROOT/JC-2025-10-14.html" "/sessions/2025/10/"
    [[ -f "$WEBROOT/jc-october-2025.html" ]] && \
      write_redirect_stub "$WEBROOT/jc-october-2025.html" "/sessions/2025/10/"
  fi

  rewrite_asset_paths
  link_check

  log "Reorganization complete"
  echo "Next:"
  echo "  • Review changes"
  echo "  • git commit"
  echo "  • git push"
  echo "  • Enable GitHub Pages → /$WEBROOT"
}

main "$@"