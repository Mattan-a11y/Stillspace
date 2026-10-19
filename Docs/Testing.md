# Preview validation

Version 1.3.4 targets macOS 14 and is developed on Apple silicon with the macOS 26 SDK. The Xcode project is included; a full Xcode build and earlier macOS/Intel compatibility still require validation.

Previously checked: rapid scene switching, missing/corrupt video fallback, player reuse, Fill/Fit persistence, scene-pack import/export, and owned-media cleanup guards. The owner reported HDMI reconnect, sleep/wake and power-source pause/resume passed. Quick-controls Settings/library actions, Escape and clean quit were exercised in the installed 1.3.4 preview. These checks are not a complete security audit or a battery-life benchmark.

The screen-saver catalog path is experimental. Reliable immediate locked-screen video remains unverified and must not be advertised as complete. Long-duration battery/memory tests, broader Spaces/restart checks, Intel/macOS 14 testing and Apple notarization remain open.

## Reproduce

- `Tests/reliability.sh`: isolated desktop engine checks. Temporarily creates desktop surfaces and removes them when done.
- `Tests/check.sh`: scene packs, media validation and filesystem guards.
- `Tests/performance.sh /tmp/stillspace-performance.jsonl`: isolated engine CPU/RSS samples with temporary synthetic video. Not a whole-app energy benchmark.

Optional checks can accept a local MP4; never commit private test media or personal preferences. README renderings use an isolated defaults domain and only original demo media. They do not apply a wallpaper or modify the live screen-saver catalog.

Publication check: Northern Drift passed real-MP4 scene-pack installation, repeat application, preservation after pack removal, malformed-manifest and filesystem-guard tests. The PNG and GIF were visually inspected. Home and Library were captured from an isolated documentation app using real project views; no personal imports were displayed.
