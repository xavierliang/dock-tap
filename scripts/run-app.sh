#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/DockTap.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
LAUNCH_DAEMONS="$CONTENTS/Library/LaunchDaemons"
BUNDLE_ID="ai.resopod.docktap"
HELPER_NAME="DockTapClosedLidHelper"
HELPER_BUNDLE_ID="$BUNDLE_ID.closedlidhelper"
HELPER_MACH_SERVICE="$HELPER_BUNDLE_ID.xpc"
LAUNCH_DAEMON_PLIST="$HELPER_BUNDLE_ID.plist"
LAUNCH_DAEMON_PLIST_SRC="$ROOT/Resources/LaunchDaemons/$LAUNCH_DAEMON_PLIST"
CODESIGN_IDENTITY="${DOCK_TAP_CODESIGN_IDENTITY:-}"
ALLOW_UNSTABLE_ADHOC="${DOCK_TAP_ALLOW_UNSTABLE_ADHOC:-}"

plist_value() {
    /usr/libexec/PlistBuddy -c "Print $1" "$2"
}

verify_launch_daemon_plist() {
    local plist="$1"
    local expected_bundle_program="Contents/Library/LaunchDaemons/$HELPER_NAME"

    /usr/bin/plutil -lint "$plist" >/dev/null

    local label
    label="$(plist_value ":Label" "$plist")"
    [[ "$label" == "$HELPER_BUNDLE_ID" ]] || {
        echo "LaunchDaemon Label mismatch: $label" >&2
        exit 1
    }

    local bundle_program
    bundle_program="$(plist_value ":BundleProgram" "$plist")"
    [[ "$bundle_program" == "$expected_bundle_program" ]] || {
        echo "LaunchDaemon BundleProgram mismatch: $bundle_program" >&2
        exit 1
    }

    local mach_service
    mach_service="$(plist_value ":MachServices:$HELPER_MACH_SERVICE" "$plist")"
    [[ "$mach_service" == "true" ]] || {
        echo "LaunchDaemon MachServices missing $HELPER_MACH_SERVICE" >&2
        exit 1
    }

    local keep_alive
    keep_alive="$(plist_value ":KeepAlive" "$plist")"
    [[ "$keep_alive" == "true" ]] || {
        echo "LaunchDaemon KeepAlive must restart after non-crash exits" >&2
        exit 1
    }
}

cd "$ROOT"

swift build -c debug --product DockTap
swift build -c debug --product "$HELPER_NAME"
BIN_DIR="$(swift build -c debug --show-bin-path)"
[[ -x "$BIN_DIR/DockTap" ]] || {
    echo "missing built executable: $BIN_DIR/DockTap" >&2
    exit 1
}
[[ -x "$BIN_DIR/$HELPER_NAME" ]] || {
    echo "missing built helper executable: $BIN_DIR/$HELPER_NAME" >&2
    exit 1
}
[[ -f "$LAUNCH_DAEMON_PLIST_SRC" ]] || {
    echo "missing LaunchDaemon plist: $LAUNCH_DAEMON_PLIST_SRC" >&2
    exit 1
}

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES" "$LAUNCH_DAEMONS"

cp "$BIN_DIR/DockTap" "$MACOS/DockTap"
cp "$BIN_DIR/$HELPER_NAME" "$LAUNCH_DAEMONS/$HELPER_NAME"
cp "$LAUNCH_DAEMON_PLIST_SRC" "$LAUNCH_DAEMONS/$LAUNCH_DAEMON_PLIST"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
for resource in DockTap.icns StatusBarIconTemplate.png StatusBarIconTemplate@2x.png; do
    cp "$ROOT/Resources/$resource" "$RESOURCES/$resource"
done
for lproj in en.lproj zh-Hans.lproj; do
    /usr/bin/ditto "$ROOT/Resources/$lproj" "$RESOURCES/$lproj"
done
chmod +x "$MACOS/DockTap"
chmod +x "$LAUNCH_DAEMONS/$HELPER_NAME"

/usr/bin/plutil -lint "$CONTENTS/Info.plist" >/dev/null
verify_launch_daemon_plist "$LAUNCH_DAEMONS/$LAUNCH_DAEMON_PLIST"

if [[ -n "$CODESIGN_IDENTITY" ]]; then
    SIGNING_MODE="stable"
    /usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --identifier "$HELPER_BUNDLE_ID" "$LAUNCH_DAEMONS/$HELPER_NAME"
    /usr/bin/codesign --force --deep --sign "$CODESIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
elif [[ "$ALLOW_UNSTABLE_ADHOC" == "1" ]]; then
    SIGNING_MODE="unstable-adhoc"
    echo "WARNING: USING UNSTABLE AD-HOC SIGNING FOR $BUNDLE_ID. ACCESSIBILITY/TCC AUTHORIZATION MAY BE LOST ON EVERY REBUILD."
    echo "WARNING: THIS IS ONLY FOR LAUNCH SMOKE TESTS, NOT FOR ACCESSIBILITY/TCC VALIDATION."
    /usr/bin/codesign --force --sign - --identifier "$HELPER_BUNDLE_ID" "$LAUNCH_DAEMONS/$HELPER_NAME"
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
/usr/bin/codesign --verify --strict --verbose=2 "$LAUNCH_DAEMONS/$HELPER_NAME"

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
