#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="DockTap"
DISPLAY_NAME="Dock Tap"
BUNDLE_ID="ai.resopod.docktap"
DEFAULT_SIGNING_IDENTITY="Developer ID Application: Shenzhen Resopod Technology Limited Company (88DYM3N4W8)"

DIST_DIR="$ROOT/dist"
WORK_DIR="$DIST_DIR/.package-mac"
APP="$WORK_DIR/$APP_NAME.app"
STALE_VISIBLE_APP="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
APP_RESOURCES="$CONTENTS/Resources"
INFO_PLIST="$ROOT/Resources/Info.plist"

SIGNING_IDENTITY="$DEFAULT_SIGNING_IDENTITY"
KEYCHAIN_PROFILE="${DOCK_TAP_NOTARY_PROFILE:-}"
SKIP_NOTARIZE=0
ARTIFACT_KIND="dmg"
TMP_NOTARY_KEY=""
FINAL_ARTIFACT=""
PACKAGE_ARTIFACT=""
FINAL_ARTIFACT_READY=0

log() {
    printf '[package-mac] %s\n' "$*"
}

fail() {
    printf '[package-mac] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: scripts/package-mac.sh [options]

Options:
  --skip-notarize               Build and sign, but do not notarize or staple.
  --zip                         Produce an internal debug zip; requires --skip-notarize.
  --keychain-profile <name>     notarytool keychain profile to use.
  --signing-identity <identity> codesign identity to use.
  -h, --help                    Show this help.

Notarization credentials are resolved in this order:
  1. --keychain-profile <name>
  2. DOCK_TAP_NOTARY_PROFILE
  3. APPLE_API_KEY, APPLE_API_KEY_ID, APPLE_API_ISSUER
EOF
}

require_arg() {
    local option="$1"
    local value="${2:-}"
    [[ -n "$value" ]] || fail "$option requires a value"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-notarize)
            SKIP_NOTARIZE=1
            shift
            ;;
        --zip)
            ARTIFACT_KIND="zip"
            shift
            ;;
        --keychain-profile)
            require_arg "$1" "${2:-}"
            KEYCHAIN_PROFILE="$2"
            shift 2
            ;;
        --signing-identity)
            require_arg "$1" "${2:-}"
            SIGNING_IDENTITY="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

if [[ "$ARTIFACT_KIND" == "zip" && "$SKIP_NOTARIZE" != "1" ]]; then
    fail "--zip is an internal debug artifact and requires --skip-notarize"
fi

cleanup() {
    if [[ -n "$TMP_NOTARY_KEY" ]]; then
        rm -f "$TMP_NOTARY_KEY"
    fi
    if [[ "$SKIP_NOTARIZE" != "1" && "$FINAL_ARTIFACT_READY" != "1" && -n "$FINAL_ARTIFACT" ]]; then
        rm -f "$FINAL_ARTIFACT"
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

require_tool() {
    command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}

require_file() {
    [[ -f "$1" ]] || fail "missing required file: $1"
}

copy_resource() {
    local resource="$1"
    require_file "$ROOT/Resources/$resource"
    /bin/cp "$ROOT/Resources/$resource" "$APP_RESOURCES/$resource"
}

write_temp_notary_key() {
    TMP_NOTARY_KEY="$(/usr/bin/mktemp "$WORK_DIR/AuthKey.XXXXXX")"
    /bin/chmod 600 "$TMP_NOTARY_KEY"
    printf '%s\n' "$1" > "$TMP_NOTARY_KEY"
}

expand_explicit_path() {
    local value="$1"
    case "$value" in
        "~/"*) printf '%s/%s' "$HOME" "${value#"~/"}" ;;
        *) printf '%s' "$value" ;;
    esac
}

prepare_notary_args() {
    NOTARY_ARGS=()
    NOTARY_SOURCE=""

    if [[ -n "$KEYCHAIN_PROFILE" ]]; then
        NOTARY_ARGS=(--keychain-profile "$KEYCHAIN_PROFILE")
        NOTARY_SOURCE="keychain-profile"
        return
    fi

    local missing=()
    [[ -n "${APPLE_API_KEY:-}" ]] || missing+=(APPLE_API_KEY)
    [[ -n "${APPLE_API_KEY_ID:-}" ]] || missing+=(APPLE_API_KEY_ID)
    [[ -n "${APPLE_API_ISSUER:-}" ]] || missing+=(APPLE_API_ISSUER)

    if [[ ${#missing[@]} -gt 0 ]]; then
        fail "missing notarization config. Provide --keychain-profile <name>, set DOCK_TAP_NOTARY_PROFILE, or set APPLE_API_KEY, APPLE_API_KEY_ID, and APPLE_API_ISSUER. Missing: ${missing[*]}"
    fi

    local key_arg
    key_arg="$(expand_explicit_path "$APPLE_API_KEY")"

    if [[ "$APPLE_API_KEY" == *"PRIVATE KEY"* ]]; then
        write_temp_notary_key "$APPLE_API_KEY"
        key_arg="$TMP_NOTARY_KEY"
    elif [[ "$APPLE_API_KEY" == *"\\n"* ]]; then
        write_temp_notary_key "$(printf '%b' "$APPLE_API_KEY")"
        key_arg="$TMP_NOTARY_KEY"
    elif [[ ! -f "$key_arg" ]]; then
        local decoded_key=""
        decoded_key="$(printf '%s' "$APPLE_API_KEY" | /usr/bin/base64 -D 2>/dev/null || true)"
        if [[ "$decoded_key" == *"PRIVATE KEY"* ]]; then
            write_temp_notary_key "$decoded_key"
            key_arg="$TMP_NOTARY_KEY"
        else
            fail "APPLE_API_KEY must be an explicit private key file path, PEM content, or base64-encoded PEM content; the configured value did not match any supported explicit form"
        fi
    fi

    NOTARY_ARGS=(--key "$key_arg" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER")
    NOTARY_SOURCE="env-api-key"
}

verify_app_signature() {
    log "Verifying app code signature"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

    local signing_details
    signing_details="$(/usr/bin/codesign -dv "$APP" 2>&1)"

    if ! printf '%s\n' "$signing_details" | /usr/bin/grep -q "^Identifier=$BUNDLE_ID$"; then
        printf '%s\n' "$signing_details" >&2
        fail "codesign identifier mismatch"
    fi
}

assess_app() {
    if /usr/sbin/spctl --assess --type execute --verbose=4 "$APP"; then
        log "Gatekeeper app assessment passed"
        return
    fi

    if [[ "$SKIP_NOTARIZE" == "1" ]]; then
        log "Gatekeeper app assessment rejected this non-notarized build; continuing"
    else
        fail "Gatekeeper app assessment failed"
    fi
}

create_dmg() {
    local artifact="$1"
    local dmg_root="$WORK_DIR/dmg-root"

    rm -rf "$dmg_root"
    mkdir -p "$dmg_root"
    /usr/bin/ditto "$APP" "$dmg_root/$APP_NAME.app"
    /bin/ln -s /Applications "$dmg_root/Applications"

    rm -f "$artifact"
    log "Creating DMG"
    /usr/bin/hdiutil create \
        -volname "$DISPLAY_NAME" \
        -srcfolder "$dmg_root" \
        -format UDZO \
        -ov \
        "$artifact"

    log "Signing DMG"
    /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$artifact"
    /usr/bin/codesign --verify --verbose=2 "$artifact"
    /usr/bin/hdiutil verify "$artifact"
}

create_zip() {
    local artifact="$1"
    local zip_root="$WORK_DIR/zip-root"

    rm -rf "$zip_root"
    mkdir -p "$zip_root"
    /usr/bin/ditto "$APP" "$zip_root/$APP_NAME.app"
    rm -f "$artifact"
    log "Creating internal debug zip"
    (
        cd "$zip_root"
        /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$artifact"
    )
}

notarize_artifact() {
    local artifact="$1"

    log "Submitting $ARTIFACT_KIND for notarization using $NOTARY_SOURCE credentials"
    /usr/bin/xcrun notarytool submit "$artifact" "${NOTARY_ARGS[@]}" --wait
}

staple_artifact() {
    local artifact="$1"

    if [[ "$ARTIFACT_KIND" == "dmg" ]]; then
        log "Stapling DMG"
        /usr/bin/xcrun stapler staple "$artifact"
        /usr/bin/xcrun stapler validate "$artifact"
    else
        log "Stapling app before final zip refresh"
        /usr/bin/xcrun stapler staple "$APP"
        /usr/bin/xcrun stapler validate "$APP"
        create_zip "$artifact"
    fi
}

verify_artifact() {
    local artifact="$1"

    [[ -f "$artifact" ]] || fail "artifact was not created: $artifact"

    if [[ "$ARTIFACT_KIND" == "dmg" ]]; then
        /usr/bin/codesign --verify --verbose=2 "$artifact"
        /usr/bin/hdiutil verify "$artifact"
        if [[ "$SKIP_NOTARIZE" != "1" ]]; then
            /usr/bin/xcrun stapler validate "$artifact"
            /usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=4 "$artifact"
        fi
    fi
}

require_tool swift
require_tool /usr/bin/codesign
require_tool /usr/bin/hdiutil
require_tool /usr/bin/xcrun
require_tool /usr/sbin/spctl
require_tool /usr/libexec/PlistBuddy
require_file "$INFO_PLIST"
require_file "$ROOT/Resources/DockTap.icns"
require_file "$ROOT/Resources/StatusBarIconTemplate.png"
require_file "$ROOT/Resources/StatusBarIconTemplate@2x.png"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
[[ -n "$VERSION" ]] || fail "CFBundleShortVersionString is empty"

NOTARY_SUFFIX=""
if [[ "$SKIP_NOTARIZE" == "1" ]]; then
    NOTARY_SUFFIX="-not-notarized"
fi

case "$ARTIFACT_KIND" in
    dmg) FINAL_ARTIFACT="$DIST_DIR/$APP_NAME-$VERSION-arm64$NOTARY_SUFFIX.dmg" ;;
    zip) FINAL_ARTIFACT="$DIST_DIR/$APP_NAME-$VERSION-arm64-debug.zip" ;;
    *) fail "unsupported artifact kind: $ARTIFACT_KIND" ;;
esac

mkdir -p "$DIST_DIR" "$WORK_DIR"
rm -f "$FINAL_ARTIFACT"
rm -rf "$STALE_VISIBLE_APP"

if [[ "$SKIP_NOTARIZE" == "1" ]]; then
    PACKAGE_ARTIFACT="$FINAL_ARTIFACT"
else
    PACKAGE_ARTIFACT="$WORK_DIR/$(basename "$FINAL_ARTIFACT")"
    log "Validating notarization configuration before build"
    prepare_notary_args
fi
rm -f "$PACKAGE_ARTIFACT"

cd "$ROOT"

log "Building release arm64 SwiftPM app"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
[[ -x "$BIN" ]] || fail "missing built executable: $BIN"

log "Assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$APP_RESOURCES"
/bin/cp "$BIN" "$MACOS/$APP_NAME"
/bin/cp "$INFO_PLIST" "$CONTENTS/Info.plist"
copy_resource DockTap.icns
copy_resource StatusBarIconTemplate.png
copy_resource StatusBarIconTemplate@2x.png
/bin/chmod +x "$MACOS/$APP_NAME"
/usr/bin/plutil -lint "$CONTENTS/Info.plist" >/dev/null

SPARKLE_FRAMEWORK_SRC="$BIN_DIR/Sparkle.framework"
[[ -d "$SPARKLE_FRAMEWORK_SRC" ]] || fail "Sparkle.framework not found at $SPARKLE_FRAMEWORK_SRC; run 'swift build -c release --arch arm64' to fetch dependencies"

log "Embedding Sparkle.framework"
mkdir -p "$CONTENTS/Frameworks"
/usr/bin/ditto "$SPARKLE_FRAMEWORK_SRC" "$CONTENTS/Frameworks/Sparkle.framework"

log "Signing Sparkle helpers bottom-up"
SPARKLE_DST="$CONTENTS/Frameworks/Sparkle.framework"
SPARKLE_CURRENT="$SPARKLE_DST/Versions/Current"
[[ -d "$SPARKLE_CURRENT" ]] || fail "Sparkle.framework/Versions/Current not found in embedded framework"

sign_if_present() {
    local target="$1"
    if [[ -e "$target" ]]; then
        /usr/bin/codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$target"
    fi
}

# Order matters: nested executables/bundles before the framework itself.
for xpc in "$SPARKLE_CURRENT/XPCServices/"*.xpc; do
    sign_if_present "$xpc"
done
sign_if_present "$SPARKLE_CURRENT/Autoupdate"
sign_if_present "$SPARKLE_CURRENT/Updater.app"
/usr/bin/codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$SPARKLE_DST"

log "Signing app with Developer ID and hardened runtime"
/usr/bin/codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
verify_app_signature

if [[ "$ARTIFACT_KIND" == "dmg" ]]; then
    create_dmg "$PACKAGE_ARTIFACT"
else
    create_zip "$PACKAGE_ARTIFACT"
fi

if [[ "$SKIP_NOTARIZE" == "1" ]]; then
    log "Notarization skipped; artifact is explicitly not notarized"
    assess_app
else
    notarize_artifact "$PACKAGE_ARTIFACT"
    staple_artifact "$PACKAGE_ARTIFACT"
    assess_app
fi

verify_artifact "$PACKAGE_ARTIFACT"

if [[ "$PACKAGE_ARTIFACT" != "$FINAL_ARTIFACT" ]]; then
    /bin/mv "$PACKAGE_ARTIFACT" "$FINAL_ARTIFACT"
fi
FINAL_ARTIFACT_READY=1

SHA256="$(/usr/bin/shasum -a 256 "$FINAL_ARTIFACT" | /usr/bin/awk '{print $1}')"
log "Artifact: $FINAL_ARTIFACT"
log "Notarization: $([[ "$SKIP_NOTARIZE" == "1" ]] && printf 'skipped' || printf 'completed')"
log "SHA-256: $SHA256"
