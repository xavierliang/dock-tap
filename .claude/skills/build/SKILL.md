---
name: build
description: Build and package Dock Tap. Use when the user asks to build, package, notarize, create a DMG, or says "打包" / "打个包".
---

# Build & Package Dock Tap

## Intent

- **Run locally**: use `scripts/run-app.sh` for a development app bundle in `build/DockTap.app`.
- **Package for distribution**: use `scripts/package-mac.sh` to build, Developer ID sign, notarize, staple, and verify a DMG.
- **Non-notarized/internal package**: use `scripts/package-mac.sh --skip-notarize` only when the user explicitly asks to skip notarization.

## macOS Package Command

Always load the user's zsh environment before running the package script:

```bash
source ~/.zshrc 2>/dev/null && scripts/package-mac.sh
```

Do not run the release package command as plain `/bin/zsh -lc scripts/package-mac.sh`; a non-interactive login zsh may not read `~/.zshrc`, which can hide the notarization environment variables.

## Signing and Notarization

Signing and notarization are separate steps:

- Signing uses the Developer ID certificate in Keychain. The package script defaults to `Developer ID Application: Shenzhen Resopod Technology Limited Company (88DYM3N4W8)`.
- Notarization uses App Store Connect API credentials from `APPLE_API_KEY`, `APPLE_API_KEY_ID`, and `APPLE_API_ISSUER`.

The API key does not sign the app. It only authenticates `xcrun notarytool submit`.

Before packaging, it is safe to check whether credentials are present, but never print secret values:

```bash
for v in APPLE_API_KEY APPLE_API_KEY_ID APPLE_API_ISSUER; do
  if [[ -n "${(P)v:-}" ]]; then
    echo "$v=set"
  else
    echo "$v=unset"
  fi
done
```

If those variables are missing, stop and report the missing variables unless the user explicitly requested `--skip-notarize`.

## Output

The signed and notarized DMG is written to:

```text
dist/DockTap-<version>-universal.dmg
```

After the script completes, report the artifact path and SHA-256 printed by the script.
