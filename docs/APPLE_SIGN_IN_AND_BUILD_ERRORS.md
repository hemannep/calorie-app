# Apple sign-in and build verification

The login screen can offer Sign in with Apple on iOS and macOS when explicitly
enabled using `--dart-define=KAYLEO_APPLE_SIGN_IN_ENABLED=true`, using Firebase's
native AppleAuthProvider flow. The default is disabled for free-team builds.
Cancellation returns to the login screen, and
buttons are disabled while authentication is pending. The existing UID-scoped
local diary is used for Apple accounts too, including accounts with private relay
email addresses.

## Required account configuration

1. In Apple Developer, enable Sign in with Apple for the App ID matching the
   bundle identifier (currently `com.rajendrapoudel.kayleo` for iOS). Use your real
   registered bundle ID consistently in Xcode and Firebase before distribution.
2. In Firebase Console → Authentication → Sign-in method, enable Apple and
   complete the provider configuration requested by Firebase. Never put an Apple
   private key into this repository or the app.
3. Install full Xcode, select its developer directory, and open
   `ios/Runner.xcworkspace`. Select your Apple development team for Runner and
   regenerate provisioning profiles with the Sign in with Apple capability.
4. Build and test on an iPhone/iPad with an Apple account, including cancellation,
   private relay email, first sign-in, repeat sign-in, and sign-out.

Reference: https://firebase.google.com/docs/auth/flutter/federated-auth

## What the supplied Android log means

- The APK built successfully. SurfaceView, renderer, lifecycle, and most Google
  Play Services messages are device diagnostics rather than application crashes.
- `Unable to resolve host firestore.googleapis.com` is a device DNS/network
  failure. Check internet access, VPN, Private DNS, and firewall settings on the
  phone; try another network. App changes cannot guarantee a reachable server.
  Local diary/outbox data remains saved and uploads retry. Cached snapshots now
  show that cloud confirmation is pending instead of claiming backup is current.
- Gradle launcher and daemon now explicitly allow native access, addressing the
  Java restricted-native-access warning in the supplied log.
- Firebase's Kotlin warning remains emitted by Flutter for these plugin versions.
  The installed plugin Gradle scripts conditionally apply legacy Kotlin only
  outside AGP 9 built-in Kotlin. Do not suppress the warning or edit the global
  pub cache as a repository fix. Track Flutter/FlutterFire compatibility and
  verify upgrades with fresh builds.

Reference: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers

## Regression checks

`.github/workflows/flutter-checks.yml` runs analysis, tests, an Android debug
build and an iOS simulator build on pushes and pull requests. Tests cover Apple
button visibility and cancellation, offline outbox preservation, and cached
snapshots. CI detects regressions; it cannot guarantee future OS, SDK, or network
changes will never cause warnings/errors.

Full Xcode 27 is now installed on this machine. For a free Apple Personal Team,
use `flutter run` for debugging or `flutter run --release` for a standalone
build. All iOS configurations now use the free-team entitlements; the `personal`
scheme remains available for compatibility. Native Apple authentication requires
restoring `Runner/Runner.entitlements` in the selected Xcode configuration,
explicitly enabling the Dart flag, and completing the external
account setup and physical-device verification above.

The device build also exposed a framework code-signing failure caused by
FinderInfo metadata in the iCloud-synced Desktop build folder. The helper keeps
generated output outside Desktop through a local `build` symlink. PyTorch's
duplicate native `dealloc` was removed, its legacy LibTorch header compatibility
is scoped to the plugin, and the Podfile preserves quotes around LibTorch linker
paths containing spaces. Profile builds now include their own CocoaPods config.
The Podfile and both shared Xcode schemes invoke build preparation themselves,
so a normal terminal build restores the symlink after `flutter clean`.

The `pytorch_lite` Swift Package Manager notice is still an upstream migration
limitation. Flutter currently uses CocoaPods for that plugin and Swift Package
Manager for the other native plugins. It is separate from the code-signing and
compiler errors fixed here. Do not disable the food model just to silence it.

## Verified iPhone deployment — 2026-10-08

The release Personal Team build installed and launched on Rajendra’s Seventeen
(iPhone 17 Pro Max, iOS 27.0.1). Flutter reported `Application running` and exited
successfully; a device screenshot confirmed the app's Progress screen rendered.
The signed app passed deep/strict verification, and its provisioning profile
includes the connected device. This profile expires on 2026-10-15; rebuild with
the command below when it expires.

```sh
./tools/run_ios.sh --personal-team -d 00008150-001C79D026D8C01C --release
```

Firebase project `kayleo-c9cca` now has an iOS app registered for
`com.rajendrapoudel.kayleo`. Its downloaded configuration, Google client ID and
callback URL, Dart Firebase options, and FlutterFire metadata agree. Analysis
reported no issues and all 129 Flutter tests passed. Interactive Google and
Apple authentication were not exercised as part of this deployment check.

VS Code now has a default `Kayleo — iPhone (opens from Home Screen)` launch
configuration. It installs a release build so launching the installed app later
does not show Flutter's iOS debug-mode warning. Its pre-launch task prepares the
safe build symlink automatically. Rosetta 2 is also installed on this Apple
Silicon Mac for any explicitly requested physical-device debug sessions.

The final project defaults were verified again after a fresh `flutter clean`,
`flutter pub get`, and plain `flutter run`, without a helper, flavor, or Dart
define. The default Runner debug build installed and launched, connected to
the Dart VM Service, and completed hot reload in 470 ms. A device screenshot
confirmed the Today screen rendered. VS Code now uses this default scheme too.
Build preparation copies freshly resolved packages before preserving the old
Desktop directory, makes the temporary generated copy writable, and removes
signing metadata there. This handles File Provider move timeouts and SwiftPM's
read-only checkouts without losing the current package resolution.

References:
- https://developer.apple.com/library/archive/qa/qa1940/_index.html
- https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers
- https://github.com/pytorch/pytorch/issues/150901
