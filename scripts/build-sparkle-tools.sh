#!/usr/bin/env bash
# Build the three Sparkle CLI tools (generate_keys, generate_appcast, sign_update)
# from the Swift sources checked out under .build/checkouts/Sparkle, and stage
# the resulting binaries in scripts/sparkle-tools/bin/ for use by release.sh.
#
# Re-run after a Sparkle version upgrade, or whenever .build/ has been cleaned.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_SRC="$ROOT/.build/checkouts/Sparkle"
BIN_DIR="$ROOT/scripts/sparkle-tools/bin"
TOOLS=(generate_keys generate_appcast sign_update)

log() {
    printf '[build-sparkle-tools] %s\n' "$*"
}

fail() {
    printf '[build-sparkle-tools] ERROR: %s\n' "$*" >&2
    exit 1
}

if [[ ! -d "$SPARKLE_SRC" ]]; then
    log "Sparkle source not found at $SPARKLE_SRC"
    log "Running 'swift build' to fetch the SPM dependency"
    (cd "$ROOT" && swift build >/dev/null)
fi

[[ -d "$SPARKLE_SRC" ]] || fail "Sparkle source still missing at $SPARKLE_SRC after swift build"

command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild not found; install Xcode command line tools"

mkdir -p "$BIN_DIR"
DERIVED="$(/usr/bin/mktemp -d)"
trap 'rm -rf "$DERIVED"' EXIT

for tool in "${TOOLS[@]}"; do
    log "Building $tool"
    xcodebuild -project "$SPARKLE_SRC/Sparkle.xcodeproj" \
               -scheme "$tool" \
               -configuration Release \
               -derivedDataPath "$DERIVED" \
               build >/dev/null
    /bin/cp "$DERIVED/Build/Products/Release/$tool" "$BIN_DIR/$tool"
done

log "Built tools: ${TOOLS[*]}"
log "Output: $BIN_DIR"
