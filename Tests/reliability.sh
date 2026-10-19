#!/bin/zsh
set -eu
cd "${0:A:h}/.."
stage="$(mktemp -d /private/tmp/stillspace-reliability.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
swiftc -module-cache-path "$stage/cache" -swift-version 5 -D STILLSPACE_CHECK -parse-as-library Sources/*.swift Tests/PlaybackCheck.swift -o "$stage/check"
"$stage/check" "$@"
