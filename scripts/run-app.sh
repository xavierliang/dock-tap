#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/DockTap.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BUNDLE_ID="ai.resopod.docktap"
CODESIGN_IDENTITY="${DOCK_TAP_CODESIGN_IDENTITY:-}"
ALLOW_UNSTABLE_ADHOC="${DOCK_TAP_ALLOW_UNSTABLE_ADHOC:-}"

cd "$ROOT"

swift build -c debug
BIN_DIR="$(swift build -c debug --show-bin-path)"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN_DIR/DockTap" "$MACOS/DockTap"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
for resource in DockTap.icns StatusBarIconTemplate.png StatusBarIconTemplate@2x.png; do
    cp "$ROOT/Resources/$resource" "$RESOURCES/$resource"
done
chmod +x "$MACOS/DockTap"

/usr/bin/plutil -lint "$CONTENTS/Info.plist" >/dev/null

if [[ -n "$CODESIGN_IDENTITY" ]]; then
    SIGNING_MODE="stable"
    /usr/bin/codesign --force --deep --sign "$CODESIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
elif [[ "$ALLOW_UNSTABLE_ADHOC" == "1" ]]; then
    SIGNING_MODE="unstable-adhoc"
    echo "WARNING: USING UNSTABLE AD-HOC SIGNING FOR $BUNDLE_ID. ACCESSIBILITY/TCC AUTHORIZATION MAY BE LOST ON EVERY REBUILD."
    echo "WARNING: THIS IS ONLY FOR LAUNCH SMOKE TESTS, NOT FOR ACCESSIBILITY/TCC VALIDATION."
    /usr/bin/codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP"
else
    cat >&2 <<'EOF'
Missing stable signing identity.

Set DOCK_TAP_CODESIGN_IDENTITY to a local code signing certificate name, for example:
  DOCK_TAP_CODESIGN_IDENTITY="Apple Development: ..." scripts/run-app.sh

Ad-hoc signing is cdhash-based and is not stable for Accessibility/TCC manual validation.
For a launch-only smoke test, opt in explicitly:
  DOCK_TAP_ALLOW_UNSTABLE_ADHOC=1 scripts/run-app.sh
EOF
    exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

SIGNING_DETAILS="$(/usr/bin/codesign -dv "$APP" 2>&1)"
DESIGNATED_REQUIREMENT="$(/usr/bin/codesign -d -r- "$APP" 2>&1)"

if ! printf '%s\n' "$SIGNING_DETAILS" | /usr/bin/grep -q "^Identifier=$BUNDLE_ID$"; then
    printf '%s\n' "$SIGNING_DETAILS"
    echo "codesign identifier mismatch" >&2
    exit 1
fi
if printf '%s\n' "$SIGNING_DETAILS" | /usr/bin/grep -q 'not bound'; then
    printf '%s\n' "$SIGNING_DETAILS"
    echo "codesign resource seal is not bound" >&2
    exit 1
fi
if printf '%s\n' "$DESIGNATED_REQUIREMENT" | /usr/bin/grep -Eq '^designated => cdhash [0-9a-fA-F]+$' \
    && [[ "$SIGNING_MODE" != "unstable-adhoc" ]]; then
    printf '%s\n' "$DESIGNATED_REQUIREMENT"
    echo "codesign designated requirement is cdhash-only; provide a stable signing identity" >&2
    exit 1
fi

printf '%s\n' "$SIGNING_DETAILS" | /usr/bin/grep -E 'Identifier=|Signature=|TeamIdentifier=|Sealed Resources'
printf '%s\n' "$DESIGNATED_REQUIREMENT" | /usr/bin/grep '^designated =>'
/usr/bin/open -n "$APP"

echo "Launched $APP"
