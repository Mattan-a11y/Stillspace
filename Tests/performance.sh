#!/bin/zsh
set -eu
cd "${0:A:h}/.."
result="${1:?Pass a report output path}"
stage="$(mktemp -d /private/tmp/stillspace-performance.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
swiftc -O -module-cache-path "$stage/cache" -swift-version 5 -D STILLSPACE_CHECK -parse-as-library Sources/*.swift Tests/PerformanceCheck.swift -o "$stage/check"
"$stage/check" generate "$stage"
: > "$result"
for mode in idle builtin 1080p 4K paused; do
    movie="$stage/1080p.mp4"
    [[ "$mode" != 4K ]] || movie="$stage/4K.mp4"
    "$stage/check" "$mode" "$movie" | tee -a "$result"
done
