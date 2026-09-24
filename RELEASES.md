# Releasing Cereal

Downloads live on [GitHub Releases](https://github.com/Neel-Sh/Cereal/releases). Cereal checks `appcast.xml` on the `main` branch for updates. Sparkle verifies each DMG against the EdDSA public key in `Cereal/Info.plist` before installing it.

## Prepare a release

1. Use a Mac with Xcode 27, [create-dmg](https://github.com/create-dmg/create-dmg) (`brew install create-dmg`), the `Developer ID Application: Neel Sharma (Q672YJ8657)` certificate, and the matching Apple account signed in to Xcode. The Sparkle private key must be in that Mac's login Keychain under account `cereal`. Back up this private key securely; losing it prevents existing installations from accepting future updates without a migration.
2. Increment both the marketing version and build number. Build numbers must always increase. Write release notes in a Markdown file.
3. Run `script/make_release.sh 1.0.1 2 release-notes.md` with the intended version and build number. It archives the app, exports with Developer ID signing, uploads it for Apple notarization, waits for a stapled app, builds a signed DMG with the layout in `docs/dmg/installer-background.svg`, and generates the Sparkle appcast. The output is `dist/Cereal.dmg` and `appcast.xml`.
4. Check the DMG and appcast before publishing:

   ```sh
   hdiutil verify dist/Cereal.dmg
   codesign --verify --verbose=2 dist/Cereal.dmg
   xcrun stapler validate /path/to/exported/Cereal.app
   xmllint --noout appcast.xml
   ```

The script also accepts `NOTARY_KEYCHAIN_PROFILE` to submit and staple the disk image itself with `notarytool`. Without that profile, the **app inside the DMG is notarized and stapled**; the disk image is Developer ID signed but has no separate notarization ticket. Do not describe the disk image itself as notarized unless `xcrun stapler validate dist/Cereal.dmg` succeeds.

## Publish

Commit the app changes and generated `appcast.xml`, push them to `main`, then attach the DMG to a GitHub Release whose tag is `vVERSION`. The URL in the appcast must exactly match the uploaded asset. For example:

```sh
git add Cereal Cereal.xcodeproj appcast.xml script README.md RELEASES.md .gitignore
git commit -m 'Release Cereal 1.0.1'
git push origin main
gh release create v1.0.1 dist/Cereal.dmg --title 'Cereal 1.0.1' --notes-file release-notes.md --target main
```

Open the public appcast URL from `Cereal/Info.plist` and the release asset URL after publishing. Install the previous release and choose **Check for Updates…** to test an actual version change. The glass banner appears for scheduled checks; manually initiated checks use Sparkle's standard update window.

The DMG is kept out of Git history and stored as a GitHub Release asset. Keep the `cereal` Sparkle private key out of the repository and never change `SUPublicEDKey` for routine releases.
