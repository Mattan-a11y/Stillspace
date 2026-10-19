# Personal installation and future release

The local build is ad-hoc signed for personal testing. It is not a notarized public release. Do not tell users to disable Gatekeeper, SIP, or other security protections.

To install or update, quit Stillspace, unpack the app ZIP, and run `install.sh /path/to/Stillspace.app`. It installs under the current user’s Applications folder, verifies the app signature, stages before replacement, keeps a previous-app rollback ZIP, and leaves the library/preferences in place. For a notarized release, Finder drag-and-drop into Applications is also supported. The script never strips quarantine. To roll back, quit the app, unpack Stillspace-Rollback.zip, and install that app with the same script. There is no automatic update/download service.

For public distribution, the owner needs a Developer ID Application certificate in Keychain and a notarytool credential profile. Store credentials using Apple’s tools yourself; do not paste passwords into chat or into scripts. Then run `release.sh /path/to/Stillspace.app 'Developer ID Application: …' profile-name`. This signs a staged copy with hardened runtime and a timestamp, submits it, requires Accepted status, staples the ticket, checks Gatekeeper assessment, and creates Stillspace-Release.zip. Uploading to Apple is a separate owner-authorized step; it has not been performed. Full Xcode may be needed for the notarization toolchain. The release script is syntax-checked but cannot be exercised end-to-end without the certificate/account.

The current command-line build targets the host architecture. A public Mac release still needs a universal build (arm64 and x86_64), deployment-target testing, and hardware acceptance on both architectures. Xcode’s standard archive/export flow is preferable for that release.

References: [Apple Developer ID](https://developer.apple.com/developer-id/), [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
