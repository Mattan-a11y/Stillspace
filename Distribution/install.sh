#!/bin/zsh
# Install an already-unpacked Stillspace.app. Run as your ordinary user.
set -eu
source_app="${1:?Pass the path to Stillspace.app}"
destination="${2:-$HOME/Applications}"
target="$destination/Stillspace.app"
[[ -d "$source_app/Contents" ]] || { print -u2 'App bundle missing.'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")" == studio.stillspace.mac ]] || { print -u2 'Unexpected app bundle.'; exit 1; }
codesign --verify --deep --strict "$source_app"
if pgrep -x Stillspace >/dev/null; then print -u2 'Quit Stillspace before installing.'; exit 1; fi
mkdir -p "$destination"
stage="$(mktemp -d "$destination/.stillspace-install.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$source_app" "$stage/Stillspace.app"
codesign --verify --deep --strict "$stage/Stillspace.app"
if [[ -e "$target" ]]; then
  ditto -c -k --keepParent "$target" "$destination/Stillspace-Rollback.zip"
  mv "$target" "$stage/Previous.app"
fi
if ! mv "$stage/Stillspace.app" "$target"; then
  [[ ! -d "$stage/Previous.app" ]] || mv "$stage/Previous.app" "$target"
  exit 1
fi
print "Installed $target. Your library and preferences were preserved."
