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
RELEASE_ARCH_LABEL="universal"

NEW_VERSION=""
NOTES_FILE=""
DRY_RUN=0

log() { printf '[release] %s\n' "$*"; }
fail() { printf '[release] ERROR: %s\n' "$*" >&2; exit 1; }

release_dmg_name() {
    local version="$1"
    printf 'DockTap-%s-%s.dmg' "$version" "$RELEASE_ARCH_LABEL"
}

legacy_arm64_dmg_name() {
    local version="$1"
    printf 'DockTap-%s-arm64.dmg' "$version"
}

parse_appcast_xml() {
    /usr/bin/ruby -rrexml/document -e 'REXML::Document.new(File.read(ARGV.fetch(0)))' "$1" >/dev/null
}

extract_appcast_enclosure_urls() {
    /usr/bin/ruby -rrexml/document -e '
        doc = REXML::Document.new(File.read(ARGV.fetch(0)))
        REXML::XPath.each(doc, "//enclosure") do |enclosure|
            url = enclosure.attributes["url"]
            puts url unless url.nil? || url.empty?
        end
    ' "$1"
}

validate_appcast_shape() {
    local appcast="$1"
    local enclosure_count=0
    local url

    [[ -f "$appcast" ]] || fail "appcast XML missing: $appcast"
    parse_appcast_xml "$appcast" || fail "appcast XML is not parseable: $appcast"

    if /usr/bin/grep -q '<sparkle:deltas' "$appcast"; then
        fail "appcast contains sparkle:deltas; delta updates must not be published"
    fi

    while IFS= read -r url; do
        [[ -n "$url" ]] || continue
        enclosure_count=$((enclosure_count + 1))
        if [[ "$url" == *".delta"* ]]; then
            fail "appcast contains delta enclosure URL: $url"
        fi
    done < <(extract_appcast_enclosure_urls "$appcast")

    [[ "$enclosure_count" -gt 0 ]] || fail "appcast contains no enclosure URLs"
}

is_2xx_status() {
    [[ "$1" =~ ^2[0-9][0-9]$ ]]
}

http_status_for_url() {
    local method="$1"
    local url="$2"
    local status

    if [[ "$method" == "HEAD" ]]; then
        status="$(curl --silent --show-error --location --head \
            --output /dev/null --write-out '%{http_code}' --max-time 20 \
            "$url" 2>/dev/null || true)"
    else
        status="$(curl --silent --show-error --location --range 0-0 \
            --output /dev/null --write-out '%{http_code}' --max-time 20 \
            "$url" 2>/dev/null || true)"
    fi

    printf '%s' "${status:-000}"
}

check_enclosure_url() {
    local url="$1"
    local attempt
    local status
    local last_method="HEAD"
    local last_status="000"

    for attempt in 1 2 3; do
        status="$(http_status_for_url HEAD "$url")"
        if is_2xx_status "$status"; then
            printf 'HEAD %s' "$status"
            return 0
        fi
        last_method="HEAD"
        last_status="$status"

        status="$(http_status_for_url GET "$url")"
        if is_2xx_status "$status"; then
            printf 'GET range %s' "$status"
            return 0
        fi
        last_method="GET range"
        last_status="$status"

        [[ "$attempt" -eq 3 ]] || sleep 2
    done

    printf '%s %s' "$last_method" "$last_status"
    return 1
}

print_appcast_validation_failure() {
    local bad_url

    {
        printf '[release] ERROR: appcast enclosure URL validation failed\n'
        printf '[release] Bad enclosure URLs:\n'
        for bad_url in "$@"; do
            printf '[release]   - %s\n' "$bad_url"
        done
        printf '[release] Manual recovery steps:\n'
        if [[ "$DRY_RUN" -eq 1 ]]; then
            printf '[release]   1. Inspect the generated appcast under %s.\n' "$STAGING"
            printf '[release]   2. Confirm the historical GitHub Release DMG assets exist.\n'
            printf '[release]   3. Re-run this dry-run after fixing missing or unreachable assets.\n'
        else
            printf '[release]   1. Do not commit or push docs/appcast.xml yet; this script stopped before that step.\n'
            printf '[release]   2. Inspect GitHub Release v%s and upload or replace any missing DMG assets.\n' "$NEW_VERSION"
            printf '[release]   3. If keeping the release, regenerate and validate docs/appcast.xml after the asset URLs return 2xx.\n'
            printf '[release]   4. If abandoning this release, delete GitHub Release v%s, delete tag v%s, revert the pushed version bump commit, then re-run.\n' "$NEW_VERSION" "$NEW_VERSION"
        fi
    } >&2
}

validate_appcast_enclosure_urls() {
    local appcast="$1"
    local skip_url="${2:-}"
    local url
    local result
    local checked_count=0
    local skipped_count=0
    local -a bad_urls=()

    log "Validating appcast XML shape"
    validate_appcast_shape "$appcast"

    log "Validating appcast enclosure URLs"
    while IFS= read -r url; do
        [[ -n "$url" ]] || continue
        if [[ -n "$skip_url" && "$url" == "$skip_url" ]]; then
            skipped_count=$((skipped_count + 1))
            log "DRY-RUN: skipped vNext enclosure URL: $url"
            continue
        fi

        if result="$(check_enclosure_url "$url")"; then
            checked_count=$((checked_count + 1))
            log "Validated enclosure URL ($result): $url"
        else
            bad_urls+=("$url [$result]")
        fi
    done < <(extract_appcast_enclosure_urls "$appcast")

    if [[ "${#bad_urls[@]}" -gt 0 ]]; then
        print_appcast_validation_failure "${bad_urls[@]}"
        return 1
    fi

    if [[ "$DRY_RUN" -eq 1 && "$skipped_count" -gt 0 && "$checked_count" -eq 0 ]]; then
        fail "dry-run skipped the vNext URL but found no historical enclosure URLs to validate"
    fi
}

usage() {
    cat <<'EOF'
Usage: scripts/release.sh <new-version> [--notes-file PATH] [--dry-run]

Options:
  --notes-file PATH  Read release notes from PATH (default: gh --generate-notes).
  --dry-run          Bump Info.plist, build DMG, generate appcast, and validate
                     enclosure URLs, but skip commits, push, and GitHub release.
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
command -v curl >/dev/null 2>&1 || fail "curl not found"
command -v /usr/libexec/PlistBuddy >/dev/null 2>&1 || fail "PlistBuddy not found"
[[ -x /usr/bin/ruby ]] || fail "ruby not found at /usr/bin/ruby"

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

DMG_NAME="$(release_dmg_name "$NEW_VERSION")"
DMG="$DIST_DIR/$DMG_NAME"
[[ -f "$DMG" ]] || fail "expected DMG missing: $DMG"

# ---- Commit version bump ------------------------------------------------------

if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: skipping version bump commit and GitHub release creation"
else
    log "Committing version bump"
    /usr/bin/git add "$INFO_PLIST"
    /usr/bin/git commit -m "Bump version to v$NEW_VERSION"
    /usr/bin/git push origin main

    # ---- Create GitHub Release ------------------------------------------------

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
fi

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
    found_historical_dmg=0
    for dmg_name in "$(release_dmg_name "$version")" "$(legacy_arm64_dmg_name "$version")"; do
        [[ -f "$STAGING/$dmg_name" ]] && { found_historical_dmg=1; break; }
        if [[ -f "$DIST_DIR/$dmg_name" ]]; then
            /bin/cp "$DIST_DIR/$dmg_name" "$STAGING/$dmg_name"
            found_historical_dmg=1
            break
        fi
        log "Downloading historical DMG for $tag: $dmg_name"
        if gh release download "$tag" --repo "$GH_REPO" --pattern "$dmg_name" --dir "$STAGING"; then
            found_historical_dmg=1
            break
        fi
    done
    if [[ "$found_historical_dmg" -eq 0 ]]; then
        log "WARN: failed to fetch a supported DMG for $tag (will be omitted from appcast)"
    fi
done < <(gh release list --repo "$GH_REPO" --json tagName --jq '.[].tagName')

# ---- Generate + post-process appcast.xml --------------------------------------

log "Generating appcast.xml"
"$SPARKLE_BIN/generate_appcast" \
    --maximum-deltas 0 \
    --download-url-prefix "$RELEASES_BASE/v$NEW_VERSION/" \
    --link "https://github.com/$GH_REPO" \
    "$STAGING"

GENERATED="$STAGING/appcast.xml"
[[ -f "$GENERATED" ]] || fail "generate_appcast did not produce $GENERATED"

# Rewrite each enclosure URL so the tag in the path matches the DMG's own
# version (extracted from the filename), rather than the global prefix tag.
log "Rewriting per-version enclosure URLs"
/usr/bin/ruby -rrexml/document -e '
    base = ARGV.fetch(0)
    path = ARGV.fetch(1)
    doc = REXML::Document.new(File.read(path))

    REXML::XPath.each(doc, "//enclosure") do |enclosure|
        url = enclosure.attributes["url"].to_s
        filename = url.split("/").last
        next unless filename =~ /\ADockTap-([0-9]+\.[0-9]+\.[0-9]+)-(?:arm64|universal)\.dmg\z/

        enclosure.attributes["url"] = "#{base}/v#{$1}/#{filename}"
    end

    formatter = REXML::Formatters::Pretty.new(4)
    formatter.compact = true
    File.open(path, "w") do |file|
        formatter.write(doc, file)
        file.write("\n")
    end
' "$RELEASES_BASE" "$GENERATED"

if [[ "$DRY_RUN" -eq 1 ]]; then
    validate_appcast_enclosure_urls \
        "$GENERATED" \
        "$RELEASES_BASE/v$NEW_VERSION/$DMG_NAME"

    trap - EXIT
    log "DRY-RUN: build, package, appcast generation, and validation succeeded"
    log "Reverting Info.plist"
    /usr/bin/git checkout -- "$INFO_PLIST"
    log "Generated appcast: $GENERATED (kept for inspection)"
    log "DMG: $DMG (kept; remove manually if not needed)"
    exit 0
fi

validate_appcast_enclosure_urls "$GENERATED"

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
