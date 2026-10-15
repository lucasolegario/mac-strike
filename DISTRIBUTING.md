# Distributing MacStrike

How to build a signed, notarized `MacStrike.app` + DMG that users can download and
open without Gatekeeper blocking it.

## One-time setup

1. **Apple Developer Program** — enroll ($99/yr) at https://developer.apple.com.
2. **Developer ID Application certificate** — in Xcode (Settings → Accounts →
   Manage Certificates → +) or on the developer portal. Install it in your login
   keychain. Verify with:
   ```bash
   security find-identity -v -p codesigning
   # look for: "Developer ID Application: Your Name (TEAMID)"
   ```
3. **App-specific password** for notarization — create one at
   https://account.apple.com (Sign-In & Security → App-Specific Passwords), then
   store notarytool credentials once:
   ```bash
   xcrun notarytool store-credentials MacStrikeNotary \
     --apple-id "you@email.com" --team-id "TEAMID" --password "xxxx-xxxx-xxxx-xxxx"
   ```

## Build a release

```bash
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE="MacStrikeNotary"
bash scripts/build-app.sh
```

This builds the release binary, assembles `MacStrike.app` (with a generated
icon), signs it with the hardened runtime + the Wine entitlements, packages a
DMG, notarizes it, and staples the ticket. The result lands in `dist/`.

Without `SIGN_IDENTITY` the script still produces an **unsigned** `.app` for local
testing (not distributable — Gatekeeper will block it on other Macs).

## Why the entitlements matter

`GUISupport/MacStrike.entitlements` grants JIT, unsigned executable memory,
library-validation bypass and dyld env vars. Wine needs all of these; a hardened,
notarized build **crashes when a game starts** without them.

## Selling it

- MacStrike's source is MIT and public, so the paid value is the **ready-made,
  signed, notarized app** + updates + support (most users won't build from source).
- Set your product id in `Sources/BottleEngine/LicenseManager.swift`
  (`LicenseConfig.current`). New users get a **7-day trial** automatically; after
  that, a license key (Gumroad / Lemon Squeezy) unlocks Pro features.
- Do **not** bundle Wine, the Apple GPTK, or any third-party binary in the app —
  MacStrike downloads them from their official sources at runtime, which keeps you
  clear of their redistribution terms.

## Releasing on GitHub

```bash
gh release create v0.1.0 dist/MacStrike-0.1.0.dmg \
  --title "MacStrike 0.1.0" --notes "First release."
```
