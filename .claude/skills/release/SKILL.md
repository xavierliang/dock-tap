---
name: release
description: Cut a new Dock Tap release end-to-end — version bump, notarized DMG, GitHub Release, Sparkle appcast publishing. Use when the user asks to release, publish, ship, cut a version, or says "发版" / "发个新版" / "release v0.x.y".
---

# Release Dock Tap

## Intent

One-command publish via `scripts/release.sh <new-version>`:
1. Bumps `CFBundleShortVersionString` (to the given version) and `CFBundleVersion` (auto-incremented) in `Resources/Info.plist`.
2. Runs `swift test`.
3. Builds + Developer ID signs + notarizes + staples a DMG via `scripts/package-mac.sh`.
4. Commits the version bump and pushes `main`.
5. Creates a GitHub Release (`gh release create vX.Y.Z`) and uploads the DMG.
6. Downloads every prior released DMG into a staging dir so the Sparkle appcast lists the full version history.
7. Generates `docs/appcast.xml` with `generate_appcast`, post-processes each enclosure URL so it points to its own version's release tag.
8. Commits `docs/appcast.xml` and pushes `main` (GitHub Pages serves the feed).

## Confirm before running

Always confirm the new version number with the user before invoking. The script enforces strict semver (`MAJOR.MINOR.PATCH`) and refuses to downgrade or repeat a version.

If the user wants to test the script without affecting GitHub or git history, suggest `--dry-run`. It builds the DMG and then reverts `Info.plist`.

For custom release notes, accept `--notes-file PATH`; otherwise the script lets `gh release create --generate-notes` synthesize from commit/PR history.

## Pre-flight (verify before invoking)

- Working tree clean, on `main`.
- `gh auth status` succeeds (run `gh auth login` if not).
- `APPLE_API_KEY` / `APPLE_API_KEY_ID` / `APPLE_API_ISSUER` set, OR `DOCK_TAP_NOTARY_PROFILE` set.
- `scripts/sparkle-tools/bin/generate_appcast` and `sign_update` exist. If missing, run `scripts/build-sparkle-tools.sh` first (one-time per machine / after Sparkle upgrade).
- Sparkle private key in macOS Keychain (`security find-generic-password -s "https://sparkle-project.org" -a ed25519`). If missing, regenerate via `scripts/sparkle-tools/bin/generate_keys` AND update `SUPublicEDKey` in `Resources/Info.plist`. Warn the user that all existing installs lose update capability if they regenerate the key.

The script itself re-checks all of the above and fails fast with a clear message.

## Command

Always load the user's zsh env first so notarization env vars are picked up:

```bash
source ~/.zshrc 2>/dev/null && scripts/release.sh <version>
```

For dry-run:

```bash
source ~/.zshrc 2>/dev/null && scripts/release.sh <version> --dry-run
```

## After release

- Print the GitHub Release URL and the appcast URL.
- Mention that GitHub Pages CDN may delay the appcast for a few minutes.
- Existing installs see the update on their next background check (≤ 24h, governed by `SUScheduledCheckInterval`).
- The script auto-reverts `Info.plist` on any failure between bump and commit, so a half-finished release does not leave the working tree dirty.

## One-time setup (only if scripts/sparkle-tools/bin is missing)

```bash
scripts/build-sparkle-tools.sh
```

## Related

- `.claude/skills/build/SKILL.md` — use when the user only wants to *build* / *package* a DMG without publishing.
