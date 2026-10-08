# Firebase authentication and diary backup

Project: `kayleo-c9cca`. Configured with FlutterFire CLI 1.4.1 using the authorized `workwithkyaleo@gmail.com` account on 2026-10-08.

## Account behavior

Production startup initializes Firebase using `DefaultFirebaseOptions.currentPlatform`. Email/password registration, sign-in, password reset, and Google sign-in use Firebase Authentication. Existing native Firebase sessions restore on startup. Passwords are never written to application preferences or Firestore. Google cancellation returns to the login screen, and controls prevent duplicate submissions. Error messages avoid exposing authentication internals.

The permissive `DemoAuthRepository` remains only as an explicitly injected test fixture. Old demo registrations are not Firebase accounts. Register a real account or use Google. Existing demo/legacy data remains under its original local storage keys; it is not silently imported into a cloud identity.

Each Firebase account uses a separate local cache, keyed by Firebase UID rather than email. Signing out retains that account's local diary and pending backup for its next login. Navigation, notifications, and sync detach from the old account.

## Firestore model

Records live under `users/{firebaseUid}/kayleoRecords/{recordId}`. Independent documents represent profile/goals, meals, saved meals, hydration entries, weight entries, activity by date, and milestone unlocks. Each envelope contains a JSON payload, schema version, deleted flag, and server timestamp. Meal photos, OS notification preferences, paid-feature flags, and sample diaries stay local.

A UID-scoped SharedPreferences outbox and baseline survive offline operation and process restart. Local changes are saved before upload and before sign-out; failed uploads retry on resume, every 30 seconds, and through Settings → Retry cloud backup. Small batches avoid a single oversized diary document. Separate records merge meals created on different devices. Concurrent edits to the same record use the latest server write; this is not collaborative field-level editing.

Only confirmed server snapshots update the local diary. Cache-only or locally pending snapshots cannot erase the diary. An entire incoming candidate is validated before changing the live state. Local photos are preserved when the same meal is restored from the cloud. Deletions use empty tombstones so other devices remove cached records; resetting tracking data preserves the Firebase Auth account.

`firestore.rules` was tested with the Auth/Firestore emulators and deployed to the production project. It restricts all access to the owning UID, limits accepted namespaces and payload sizes, and rejects unrelated fields. Previous deny-all rules are preserved in `docs/firebase/previous-firestore-rules.json`. No production test accounts or diary entries were created.

## Platform setup

- Android app: `com.example.calorie_app`. SHA-1 and SHA-256 for the current debug signing certificate are registered. The release build currently also uses that certificate. A future production/Play signing certificate requires registering its fingerprints and refreshing `google-services.json`.
- Android configuration contains native and web OAuth clients required by Google sign-in.
- iOS app: `com.rajendrapoudel.kayleo` (Firebase nickname: Kayleo iPhone).
  macOS retains `com.example.calorieApp`. Google client and callback URL scheme
  are configured separately in each Info.plist. macOS has Google keychain sharing
  and network client entitlements. Firebase requires iOS 15 or later; the current
  Xcode project uses iOS 27 for this connected-device setup.
- Web uses Firebase Google popup authentication. Existing authorized domains include localhost and the project's Firebase hosting domains. Add your real domain in Firebase Authentication before hosting elsewhere.

Email/password and Google providers were already enabled and were verified through the Firebase Admin configuration API. Configuration files contain normal client identifiers/API keys, not service-account private keys.

## Verification

- All 127 Flutter regression tests passed. Tests include cloud restoration, local photo preservation, atomic rejection of malformed snapshots, remote deletion, sample exclusion, offline outbox recovery, sign-out, UID isolation, independent meal merging, Google cancellation, and password-reset UI.
- All 3 Firebase emulator tests passed. They check real registration/password verification, duplicate account rejection, stable UID, owner-only rules, unauthenticated access rejection, schema limits, and tombstones.
- Run app tests: `rtk proxy flutter test`.
- Run emulator tests: `rtk proxy firebase emulators:exec --only auth,firestore --project demo-kayleo 'cd tools/firebase_test && npm test'`.
- Test-only Node dependencies use a patched gRPC override; npm audit reports zero vulnerabilities.

The release web app was observed signed in as the project owner, with “Cloud backup up to date” displayed in Settings. Android and web release builds passed, and Flutter analysis reported no issues. The final Android APK is `output/apk/kayleo-release.apk`; hashes and counts are recorded in `docs/FIREBASE_VERIFICATION.json`.

A phone was not connected during verification. Real Google account chooser/consent and native session restoration still require a device check. iOS/macOS native builds have not been verified in this task. Existing PyTorch native libraries remain a separate 16 KB page-alignment limitation documented in the previous fixes.
