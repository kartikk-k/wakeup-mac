# Releasing Wakeup

This project ships as a universal (Apple Silicon + Intel) `.dmg` attached to a
GitHub Release. The app checks GitHub Releases for updates from inside the app.

## One-time setup (for signed + notarized builds)

You need a paid **Apple Developer account** ($99/yr) for a clean, warning-free install.
Without it you can still ship an ad-hoc DMG (users right-click → Open the first time).

1. **Create a "Developer ID Application" certificate**
   - Xcode → Settings → Accounts → Manage Certificates → **+** → *Developer ID Application*.
   - Confirm it's installed: `security find-identity -v -p codesigning`
   - Note the identity string, e.g. `Developer ID Application: Your Name (ABCDE12345)`.

2. **Create an app-specific password** for notarization
   - <https://appleid.apple.com> → Sign-In & Security → App-Specific Passwords.

3. **Store a notarytool profile** (used by the local build script)
   ```sh
   xcrun notarytool store-credentials wakeup-notary \
     --apple-id "you@example.com" \
     --team-id "ABCDE12345" \
     --password "your-app-specific-password"
   ```

## Local release build

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (ABCDE12345)" \
TEAM_ID=ABCDE12345 \
NOTARY_PROFILE=wakeup-notary \
./scripts/build_dmg.sh
```

Output: `build/Wakeup-<version>.dmg`, universal, signed, notarized, and stapled.

Omit the env vars to produce an ad-hoc DMG (no Apple account required):

```sh
./scripts/build_dmg.sh
```

## Cutting a release (manual, from this machine)

1. Bump the version in Xcode (target **Wakeup** → General → **Version**), which sets
   `MARKETING_VERSION`. Optionally bump the build number (`CURRENT_PROJECT_VERSION`).
2. Build the DMG:
   ```sh
   # signed + notarized (see setup above)
   SIGN_IDENTITY="Developer ID Application: Your Name (ABCDE12345)" \
   TEAM_ID=ABCDE12345 NOTARY_PROFILE=wakeup-notary ./scripts/build_dmg.sh

   # or ad-hoc (no Apple account)
   ./scripts/build_dmg.sh
   ```
3. Commit and push any version bump:
   ```sh
   git commit -am "Release vX.Y.Z"
   git push origin main
   ```
4. Tag and publish the release with the DMG attached:
   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   gh release create vX.Y.Z build/Wakeup-X.Y.Z.dmg \
     --repo kartikk-k/wakeup-mac --title "Wakeup X.Y.Z" --notes "..."
   ```

The in-app updater compares the release tag against `CFBundleShortVersionString`, so
**the tag must match the app version** (a leading `v` is fine — `vX.Y.Z` vs app version
`X.Y.Z`).

## How the in-app updater works

`UpdateChecker.swift` queries
`https://api.github.com/repos/kartikk-k/wakeup-mac/releases/latest`, parses the tag,
and compares it to the running app's version. If newer, it offers to open the release
page to download the new DMG. It checks automatically at most once per day (toggleable
in the menu) and can be triggered manually via **Check for Updates…**.

> If you rename or move the repo, update `repo` in `UpdateChecker.swift`.
