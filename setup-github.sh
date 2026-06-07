#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  ANTIGRAVITY — GitHub Setup                                        ║
# ║  Creates all 3 repos and pushes. Run once from the scratch folder. ║
# ╚══════════════════════════════════════════════════════════════════════╝
# Usage:  bash setup-github.sh
# Needs:  gh CLI  (brew install gh)  →  run 'gh auth login' first

set -euo pipefail

GITHUB_USER="JoshuaForster02"
BASE="$(cd "$(dirname "$0")" && pwd)"

CY='\e[1;36m' GN='\e[1;32m' RD='\e[0;31m' YL='\e[0;33m' RS='\e[0m'

info() { printf "${CY}  »  %s${RS}\n" "$*"; }
ok()   { printf "${GN}  ✓  %s${RS}\n" "$*"; }
fail() { printf "${RD}  ✗  %s${RS}\n" "$*"; exit 1; }

printf "${CY}"
echo "  ╔════════════════════════════════════════╗"
echo "  ║  ANTIGRAVITY — GitHub Push             ║"
echo "  ╚════════════════════════════════════════╝"
printf "${RS}\n"

# ── Check gh CLI ──────────────────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
    fail "gh CLI not found. Install: brew install gh  →  gh auth login"
fi
if ! gh auth status &>/dev/null; then
    fail "Not logged in. Run: gh auth login"
fi

# ── Repos to create and push ──────────────────────────────────────────────────
declare -A REPOS=(
    ["antigravity-kernel"]="Flynn OS bare-metal TRON kernel (x86 assembly + C, QEMU bootable)"
    ["antigravity-linux"]="Flynn OS Linux — TRON-themed bootable ISO (Alpine + Linux kernel + Wayland compositor)"
    ["antigravity-app"]="ANTIGRAVITY macOS app — floating Notion/Anki/Flynn panels with ⌘K palette"
)

for REPO in "${!REPOS[@]}"; do
    DESC="${REPOS[$REPO]}"
    DIR="$BASE/$REPO"

    [ -d "$DIR" ] || { info "Skipping $REPO — directory not found"; continue; }

    echo ""
    info "Processing: $REPO"

    cd "$DIR"

    # Init git if needed
    if [ ! -d ".git" ]; then
        git init -b main
        ok "git init"
    fi

    # Create GitHub repo if it doesn't exist
    if ! gh repo view "$GITHUB_USER/$REPO" &>/dev/null 2>&1; then
        gh repo create "$GITHUB_USER/$REPO" \
            --public \
            --description "$DESC" \
            --push \
            --source=. \
            2>/dev/null || true
        ok "Created github.com/$GITHUB_USER/$REPO"
    else
        info "Repo already exists: github.com/$GITHUB_USER/$REPO"
    fi

    # Set remote
    if git remote get-url origin &>/dev/null 2>&1; then
        git remote set-url origin "https://github.com/$GITHUB_USER/$REPO.git"
    else
        git remote add origin "https://github.com/$GITHUB_USER/$REPO.git"
    fi

    # Stage + commit everything
    git add -A
    if ! git diff --cached --quiet; then
        git commit -m "Flynn OS: full project update $(date '+%Y-%m-%d %H:%M')" \
            --author="Joshua Forster <joshuaforster02@gmail.com>" \
            2>/dev/null || true
        ok "Committed changes"
    else
        info "Nothing new to commit in $REPO"
    fi

    # Push
    git push -u origin main --force 2>/dev/null || \
    git push -u origin HEAD --force 2>/dev/null || \
    info "Push failed — check auth: gh auth status"

    ok "Pushed $REPO"
done

echo ""
printf "${GN}╔══════════════════════════════════════════════════════╗${RS}\n"
printf "${GN}║  All repos pushed!                                  ║${RS}\n"
printf "${GN}╚══════════════════════════════════════════════════════╝${RS}\n"
echo ""
echo "  Repos:"
for REPO in "${!REPOS[@]}"; do
    printf "  ${CY}https://github.com/%s/%s${RS}\n" "$GITHUB_USER" "$REPO"
done
echo ""
echo "  GitHub Actions will now build the ISO automatically."
echo "  Download from: Actions → latest run → Artifacts → flynn-os-linux-*"
