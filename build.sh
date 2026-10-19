#!/bin/zsh
set -eu
cd "${0:A:h}"
stage="$(mktemp -d /private/tmp/stillspace-build.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
cache="$stage/ModuleCache"
mkdir -p "$cache"
app="$stage/Stillspace.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -module-cache-path "$cache" -swift-version 5 -O -parse-as-library -target "$(uname -m)-apple-macosx14.0" Sources/*.swift -o "$app/Contents/MacOS/Stillspace"
cp Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --norsrc --keepParent "$app" Stillspace.zip
printf 'Built Stillspace 1.3.4\n'
