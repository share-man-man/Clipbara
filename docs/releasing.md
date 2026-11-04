# Releasing the DMG Build

These steps are for the maintainer. They need the EdDSA private key in the macOS Keychain and write access to the release repository and the Homebrew tap.

## Steps

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Clipbara/Info.plist`.
2. Commit the code changes.
3. Build the DMG: `bash scripts/build-release.sh`. It signs the DMG with EdDSA and updates `appcast.xml`.
4. Fix up `appcast.xml`. Both parts are required:
   - **Add an item for the new version.** The script only overwrites the signature and length of the first item; it never adds one. Add the new item above the current first item, with the right `sparkle:version`, `sparkle:shortVersionString`, URL, release notes, EdDSA signature and length.
   - **Use the v-prefixed file name in the URL:** `Clipbara-v{VERSION}.dmg`. Existing release URLs and the Homebrew cask use it.
   - **Restore the previous item's signature and length.** The script writes the new build's `sparkle:edSignature` and `length` into the first item, which is the previous release. Get the original values with `git show HEAD:appcast.xml` and put them back, or Sparkle updates from that version break.
5. Commit and push `appcast.xml`.
6. Create the GitHub release, upload both DMGs, and verify them:
   ```bash
   git tag v{VERSION} && git push origin v{VERSION}
   cp build/Clipbara-{VERSION}.dmg /tmp/Clipbara-v{VERSION}.dmg
   gh release create v{VERSION} build/Clipbara-{VERSION}.dmg /tmp/Clipbara-v{VERSION}.dmg --title "v{VERSION}" --notes "..."
   ```
   Download both and check that each SHA-256 matches the one the build script printed:
   ```bash
   gh release download v{VERSION} -p "Clipbara-*.dmg" -D /tmp/verify --clobber
   shasum -a 256 /tmp/verify/Clipbara-*.dmg
   ```
7. (Optional) Update the Homebrew tap (`mobrava/homebrew-tap`): change `version` and `sha256` in `Casks/pasteclip.rb` (the build script prints the SHA-256). The cask URL uses `Clipbara-v{VERSION}.dmg`, uploaded in step 6. Update it through the GitHub API: `gh api repos/mobrava/homebrew-tap/contents/Casks/pasteclip.rb --method PUT ...`
8. If Gatekeeper complains: `xattr -cr /Applications/Clipbara.app`

Don't add a CI workflow for releases. The DMGs without the v prefix used to arrive "damaged" because of `.github/workflows/release.yml`, not GitHub: on every tag push it rebuilt an unsigned DMG under the same name and replaced the release notes. That workflow was removed.

## Sparkle

- Sparkle 2.x comes in through SPM and updates the DMG build in place.
- Appcast URL: `https://raw.githubusercontent.com/mobrava/Clipbara/main/appcast.xml`
- The EdDSA private key lives in the macOS Keychain, where `sign_update` finds it. The public key is `SUPublicEDKey` in Info.plist, which is safe to publish.
- `CheckForUpdatesViewModel` (`Services/UpdaterService.swift`) reaches views as an `@EnvironmentObject`.

## Code Signing

The build script signs ad-hoc and re-signs with a designated requirement based on the identifier. Sign inside out: Sparkle's XPC services (`Installer.xpc`, `Downloader.xpc`), then `Autoupdate` and `Updater.app`, then `Sparkle.framework`, then the app bundle. If only the app is re-signed and the XPC services are skipped, the signature chain doesn't match and Sparkle fails with "An error occurred while launching the installer".
