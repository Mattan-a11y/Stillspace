#!/bin/zsh
# Requires a Developer ID Application certificate and a stored notarytool profile.
set -eu
app="${1:?Pass a freshly built Stillspace.app}"
identity="${2:?Pass your Developer ID Application certificate name}"
profile="${3:?Pass your stored notarytool credentials profile name}"
[[ "$identity" == 'Developer ID Application:'* ]] || { print -u2 'A Developer ID Application identity is required.'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == studio.stillspace.mac ]] || { print -u2 'Unexpected app bundle.'; exit 1; }
stage="$(mktemp -d /private/tmp/stillspace-release.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Stillspace.app"
codesign --force --options runtime --timestamp --sign "$identity" "$stage/Stillspace.app"
codesign --verify --deep --strict "$stage/Stillspace.app"
ditto -c -k --keepParent "$stage/Stillspace.app" "$stage/submit.zip"
xcrun notarytool submit "$stage/submit.zip" --keychain-profile "$profile" --wait --output-format json > "$stage/notarization.json"
[[ "$(plutil -extract status raw "$stage/notarization.json")" == Accepted ]] || { cat "$stage/notarization.json"; exit 1; }
xcrun stapler staple "$stage/Stillspace.app"
xcrun stapler validate "$stage/Stillspace.app"
spctl --assess --type execute --verbose "$stage/Stillspace.app"
ditto -c -k --keepParent "$stage/Stillspace.app" ./Stillspace-Release.zip
print 'Created signed, notarized Stillspace-Release.zip.'
