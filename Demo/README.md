# Northern Drift

An original procedural wallpaper created for demonstrating Stillspace. No external photos, characters, audio, generative-image output or third-party wallpaper files were used.

- `Northern-Drift.mp4`: 1920 × 1080 H.264, 30 fps, eight-second silent loop.
- `Northern-Drift.gif`: smaller animated preview for README display, not the playback source.
- `Northern-Drift.png`: full-resolution still preview.

## License

The Northern Drift MP4, GIF, PNG and `Tools/RenderDemo.swift` are dedicated to the public domain under **CC0 1.0 Universal**: https://creativecommons.org/publicdomain/zero/1.0/

You may use, modify and share this demo, including commercially, without requesting permission. Attribution is optional. This dedication applies only to these demo files and their generator, not the Stillspace application or its other artwork.

## Recreate

On macOS with Apple Command Line Tools:

```sh
swiftc -O -parse-as-library Tools/RenderDemo.swift -o /tmp/stillspace-render-demo
/tmp/stillspace-render-demo /tmp/Stillspace-Northern-Drift
```

Use a new destination directory; the renderer refuses to overwrite an existing MP4. The output is verified for duration and resolution. No installation, network access, desktop setting changes or third-party dependencies are needed.
