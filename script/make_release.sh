#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: script/make_release.sh VERSION BUILD_NUMBER [release-notes.md]}"
BUILD_NUMBER="${2:?usage: script/make_release.sh VERSION BUILD_NUMBER [release-notes.md]}"
NOTES_FILE="${3:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp/}cereal-release.XXXXXX")"
ARCHIVE="$WORK_DIR/Cereal.xcarchive"
EXPORT_OPTIONS="$WORK_DIR/ExportOptions.plist"
NOTARIZED_APP=""
STAGING="$WORK_DIR/dmg"
UPDATES="$WORK_DIR/updates"
DMG="$ROOT_DIR/dist/Cereal-$VERSION.dmg"
SPARKLE_KEY_FILE="$WORK_DIR/sparkle.private"
SIGNING_IDENTITY="Developer ID Application: Neel Sharma (Q672YJ8657)"

cleanup() {
    if [[ -e "$SPARKLE_KEY_FILE" ]]; then rm "$SPARKLE_KEY_FILE"; fi
}
trap cleanup EXIT

mkdir -p "$ROOT_DIR/dist" "$STAGING" "$UPDATES"

xcodebuild -project "$ROOT_DIR/Cereal.xcodeproj" -scheme Cereal \
    -configuration Release -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" -derivedDataPath "$WORK_DIR/DerivedData" \
    -clonedSourcePackagesDirPath "$WORK_DIR/packages" \
    CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$SIGNING_IDENTITY" \
    DEVELOPMENT_TEAM=Q672YJ8657 "MARKETING_VERSION=$VERSION" \
    "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" archive

cat > "$EXPORT_OPTIONS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>destination</key><string>upload</string>
<key>signingStyle</key><string>manual</string>
<key>signingCertificate</key><string>Developer ID Application</string>
<key>teamID</key><string>Q672YJ8657</string>
</dict></plist>
PLIST

# Xcode re-signs Sparkle's nested helpers and uploads the app to Apple's notary service.
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportPath "$WORK_DIR/upload" -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates

for attempt in {1..40}; do
    EXPORT_DIR="$WORK_DIR/notarized-$attempt"
    if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" \
        -exportPath "$EXPORT_DIR" >/dev/null 2>&1 \
        && xcrun stapler validate "$EXPORT_DIR/Cereal.app" >/dev/null 2>&1; then
        NOTARIZED_APP="$EXPORT_DIR/Cereal.app"
        break
    fi
    if [[ "$attempt" -eq 40 ]]; then
        echo "Notarization did not finish within 20 minutes. Inspect the archive in Xcode Organizer." >&2
        exit 1
    fi
    sleep 30
done

codesign --verify --deep --strict --verbose=2 "$NOTARIZED_APP"
spctl -a -vv -t execute "$NOTARIZED_APP"
/usr/bin/ditto "$NOTARIZED_APP" "$STAGING/Cereal.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname Cereal -srcfolder "$STAGING" -ov -format UDZO \
    -fs HFS+ "$DMG"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG"

# Optional: submit and staple the disk image itself when a notarytool profile exists.
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

hdiutil verify "$DMG"
codesign --verify --verbose=2 "$DMG"

SPARKLE_BIN="$(find "$WORK_DIR/packages" -type f -name generate_appcast -print -quit)"
GENERATE_KEYS="$(find "$WORK_DIR/packages" -type f -name generate_keys -print -quit)"
if [[ -z "$SPARKLE_BIN" || -z "$GENERATE_KEYS" ]]; then
    echo "Sparkle release tools were not found in Xcode's package artifacts." >&2
    exit 1
fi

cp "$DMG" "$UPDATES/"
if [[ -f "$ROOT_DIR/appcast.xml" ]]; then cp "$ROOT_DIR/appcast.xml" "$UPDATES/appcast.xml"; fi
if [[ -n "$NOTES_FILE" ]]; then cp "$NOTES_FILE" "$UPDATES/Cereal-$VERSION.md"; fi
umask 077
"$GENERATE_KEYS" --account cereal -x "$SPARKLE_KEY_FILE"
"$SPARKLE_BIN" --ed-key-file "$SPARKLE_KEY_FILE" \
    --download-url-prefix "https://github.com/Neel-Sh/Cereal/releases/download/v$VERSION/" \
    --maximum-deltas 0 --embed-release-notes "$UPDATES"
cp "$UPDATES/appcast.xml" "$ROOT_DIR/appcast.xml"

echo "Prepared $DMG and $ROOT_DIR/appcast.xml"
shasum -a 256 "$DMG"
