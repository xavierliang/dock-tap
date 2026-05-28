#!/usr/bin/env bash
# End-to-end Dock Tap release: version bump, notarized DMG, GitHub Release,
# and Sparkle appcast publishing.
#
# Usage:
#   scripts/release.sh <new-version> [--notes-file PATH] [--dry-run]
#
# Examples:
#   scripts/release.sh 0.2.0
#   scripts/release.sh 0.2.0 --notes-file CHANGELOG-0.2.0.md
#   scripts/release.sh 0.2.0 --dry-run
#
# Pre-conditions (the script checks these and fails fast if not met):
#   - git working tree clean, current branch is main, tag vNEW_VERSION absent
#   - gh CLI authenticated
#   - APPLE_API_KEY / APPLE_API_KEY_ID / APPLE_API_ISSUER set (or DOCK_TAP_NOTARY_PROFILE)
#   - scripts/sparkle-tools/bin/{generate_appcast,sign_update} present
#   - Sparkle private key present in macOS Keychain
#   - NEW_VERSION strictly greater than current CFBundleShortVersionString

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

INFO_PLIST="$ROOT/Resources/Info.plist"
DIST_DIR="$ROOT/dist"
DOCS_APPCAST="$ROOT/docs/appcast.xml"
SPARKLE_BIN="$ROOT/scripts/sparkle-tools/bin"
GH_REPO_OWNER="xavierliang"
GH_REPO_NAME="dock-tap"
GH_REPO="$GH_REPO_OWNER/$GH_REPO_NAME"
RELEASES_BASE="https://github.com/$GH_REPO/releases/download"

NEW_VERSION=""
NOTES_FILE=""
DRY_RUN=0

log() { printf '[release] %s\n' "$*"; }
fail() { printf '[release] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: scripts/release.sh <new-version> [--notes-file PATH] [--dry-run]

Options:
  --notes-file PATH  Read release notes from PATH (default: gh --generate-notes).
  --dry-run          Bump Info.plist + build DMG, but skip commits, push, and GitHub.
                     Reverts Info.plist on success.
  -h, --help         Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --notes-file)
            [[ -n "${2:-}" ]] || fail "--notes-file requires a path"
            NOTES_FILE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            fail "unknown option: $1"
            ;;
        *)
            [[ -z "$NEW_VERSION" ]] || fail "version already set to $NEW_VERSION"
            NEW_VERSION="$1"
            shift
            ;;
    esac
done

[[ -n "$NEW_VERSION" ]] || { usage; exit 1; }
[[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be MAJOR.MINOR.PATCH, got: $NEW_VERSION"
[[ -z "$NOTES_FILE" || -f "$NOTES_FILE" ]] || fail "notes file not found: $NOTES_FILE"

# ---- Preflight ----------------------------------------------------------------

log "Pre-flight"

command -v gh >/dev/null 2>&1 || fail "gh CLI not found"
command -v /usr/libexec/PlistBuddy >/dev/null 2>&1 || fail "PlistBuddy not found"

if [[ -n "$(git status --porcelain)" ]]; then
    git status --short >&2
    fail "git working tree is not clean"
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$CURRENT_BRANCH" == "main" ]] || fail "must be on 'main' branch, currently on '$CURRENT_BRANCH'"

gh auth status >/dev/null 2>&1 || fail "gh is not authenticated (run: gh auth login)"

if [[ "$DRY_RUN" -eq 0 ]]; then
    if git rev-parse "v$NEW_VERSION" >/dev/null 2>&1; then
        fail "tag v$NEW_VERSION already exists locally"
    fi
    if gh release view "v$NEW_VERSION" >/dev/null 2>&1; then
        fail "GitHub release v$NEW_VERSION already exists"
    fi
fi

CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
CURRENT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
[[ "$NEW_VERSION" != "$CURRENT_VERSION" ]] || fail "new version equals current ($CURRENT_VERSION)"

SMALLER="$(printf '%s\n%s\n' "$NEW_VERSION" "$CURRENT_VERSION" | /usr/bin/sort -V | /usr/bin/head -n 1)"
[[ "$SMALLER" == "$CURRENT_VERSION" ]] || fail "new version $NEW_VERSION must be > current $CURRENT_VERSION"

[[ -x "$SPARKLE_BIN/generate_appcast" ]] || fail "Sparkle tools missing; run scripts/build-sparkle-tools.sh"
[[ -x "$SPARKLE_BIN/sign_update" ]]      || fail "Sparkle tools missing; run scripts/build-sparkle-tools.sh"

if ! /usr/bin/security find-generic-password -s "https://sparkle-project.org" -a ed25519 >/dev/null 2>&1; then
    fail "Sparkle private key not in Keychain (run scripts/sparkle-tools/bin/generate_keys, then back it up)"
fi

# Notarization credentials: either DOCK_TAP_NOTARY_PROFILE or the API key trio.
if [[ -z "${DOCK_TAP_NOTARY_PROFILE:-}" ]]; then
    for v in APPLE_API_KEY APPLE_API_KEY_ID APPLE_API_ISSUER; do
        [[ -n "${!v:-}" ]] || fail "missing $v (or set DOCK_TAP_NOTARY_PROFILE)"
    done
fi

log "Current: v$CURRENT_VERSION (build $CURRENT_BUILD)"
log "Next:    v$NEW_VERSION (build $((CURRENT_BUILD + 1)))"
[[ "$DRY_RUN" -eq 0 ]] || log "Mode:    DRY-RUN (will revert Info.plist on success)"

# ---- Version bump -------------------------------------------------------------

NEW_BUILD=$((CURRENT_BUILD + 1))

log "Bumping Info.plist: $CURRENT_VERSION -> $NEW_VERSION, build $CURRENT_BUILD -> $NEW_BUILD"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$INFO_PLIST"

# If anything below this point fails, revert the Info.plist on exit.
revert_plist_on_failure() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "Reverting Info.plist due to failure"
        /usr/bin/git checkout -- "$INFO_PLIST" 2>/dev/null || true
    fi
    exit $exit_code
}
trap revert_plist_on_failure EXIT

# ---- Test + package -----------------------------------------------------------

log "Running tests"
swift test >/dev/null

log "Packaging notarized DMG"
"$ROOT/scripts/package-mac.sh"

DMG="$DIST_DIR/DockTap-$NEW_VERSION-arm64.dmg"
[[ -f "$DMG" ]] || fail "expected DMG missing: $DMG"

# ---- Dry-run exit -------------------------------------------------------------

if [[ "$DRY_RUN" -eq 1 ]]; then
    trap - EXIT
    log "DRY-RUN: build + package succeeded"
    log "Reverting Info.plist"
    /usr/bin/git checkout -- "$INFO_PLIST"
    log "DMG: $DMG (kept; remove manually if not needed)"
    exit 0
fi

# ---- Commit version bump ------------------------------------------------------

log "Committing version bump"
/usr/bin/git add "$INFO_PLIST"
/usr/bin/git commit -m "Bump version to v$NEW_VERSION"
/usr/bin/git push origin main

# ---- Create GitHub Release ----------------------------------------------------

log "Creating GitHub release v$NEW_VERSION"
NOTES_ARGS=()
if [[ -n "$NOTES_FILE" ]]; then
    NOTES_ARGS=(--notes-file "$NOTES_FILE")
else
    NOTES_ARGS=(--generate-notes)
fi
gh release create "v$NEW_VERSION" "$DMG" \
    --repo "$GH_REPO" \
    --title "v$NEW_VERSION" \
    "${NOTES_ARGS[@]}"

# ---- Assemble staging dir with every published DMG ---------------------------

STAGING="$DIST_DIR/appcast-staging"
log "Assembling appcast staging at $STAGING"
rm -rf "$STAGING"
mkdir -p "$STAGING"
/bin/cp "$DMG" "$STAGING/"

# Download every other released DMG so generate_appcast emits a complete feed.
while IFS= read -r tag; do
    [[ -n "$tag" ]] || continue
    [[ "$tag" != "v$NEW_VERSION" ]] || continue
    version="${tag#v}"
    dmg_name="DockTap-$version-arm64.dmg"
    [[ -f "$STAGING/$dmg_name" ]] && continue
    if [[ -f "$DIST_DIR/$dmg_name" ]]; then
        /bin/cp "$DIST_DIR/$dmg_name" "$STAGING/$dmg_name"
        continue
    fi
    log "Downloading historical DMG for $tag"
    gh release download "$tag" --repo "$GH_REPO" --pattern "$dmg_name" --dir "$STAGING" \
        || log "WARN: failed to fetch $dmg_name for $tag (will be omitted from appcast)"
done < <(gh release list --repo "$GH_REPO" --json tagName --jq '.[].tagName')

# ---- Generate + post-process appcast.xml --------------------------------------

log "Generating appcast.xml"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "$RELEASES_BASE/v$NEW_VERSION/" \
    --link "https://github.com/$GH_REPO" \
    "$STAGING"

GENERATED="$STAGING/appcast.xml"
[[ -f "$GENERATED" ]] || fail "generate_appcast did not produce $GENERATED"

# Rewrite each enclosure URL so the tag in the path matches the DMG's own
# version (extracted from the filename), rather than the global prefix tag.
log "Rewriting per-version enclosure URLs"
ESCAPED_BASE="$(printf '%s' "$RELEASES_BASE" | /usr/bin/sed -e 's|[\\/.]|\\&|g')"
/usr/bin/sed -E -i.bak \
    "s|($ESCAPED_BASE)/v[0-9]+\\.[0-9]+\\.[0-9]+/DockTap-([0-9]+\\.[0-9]+\\.[0-9]+)-arm64\\.dmg|\\1/v\\2/DockTap-\\2-arm64.dmg|g" \
    "$GENERATED"
rm -f "$GENERATED.bak"

# ---- Commit appcast -----------------------------------------------------------

log "Updating $DOCS_APPCAST"
mkdir -p "$(dirname "$DOCS_APPCAST")"
/bin/cp "$GENERATED" "$DOCS_APPCAST"

/usr/bin/git add "$DOCS_APPCAST"
/usr/bin/git commit -m "Publish appcast v$NEW_VERSION"
/usr/bin/git push origin main

trap - EXIT

cat <<EOF

================================================================================
Released v$NEW_VERSION

  DMG:     $DMG
  Release: https://github.com/$GH_REPO/releases/tag/v$NEW_VERSION
  Appcast: https://$GH_REPO_OWNER.github.io/$GH_REPO_NAME/appcast.xml
           (GitHub Pages CDN may delay propagation by a few minutes)

Existing installs will see the update on their next background check (<= 24h).
================================================================================
EOF
