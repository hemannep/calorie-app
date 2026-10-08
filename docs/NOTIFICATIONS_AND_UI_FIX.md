# Barcode, notifications, milestones and UI

## Completed behavior

Today places barcode and food search inside the meal-entry panel. The Log a meal barcode chip opens the real scanner/product lookup screen; the demo panel is removed. Returning preserves the text draft. Successful lookup returns a boolean success so the surrounding logging flow closes correctly.

Profile has an identity/goal card, daily goals, habit statistics and labeled settings groups. Progress offers 21 persistent milestones with progress indicators and individual compliments. Milestones cover logging, calendar days, best logging streak, hydration/protein goal days and meal shortcuts. Sample data is excluded. Existing records migrate silently, earned badges remain earned, and completion compliments stay in the inbox.

## Device reminders

In **You → Notifications**, choose **Enable device notifications**, allow the OS permission, then use **Send test notification**. Android/iOS scheduling uses the device timezone and works offline after scheduling. Meal prompts are around 12:30 PM and 7:30 PM, water around 10 AM/2 PM/6 PM, and weekly review on Sunday around 6 PM. Quiet hours defer overnight milestone alerts to 8 AM. Android uses inexact allow-while-idle alarms; OS battery policy may delay delivery.

The service serializes updates, retries failures, cancels schedules on sign-out/reset/account switch or category disable, and preserves deferred celebrations when restarting the same account. Stable notification IDs and per-account delivery markers prevent repeated congratulations. Permission is requested explicitly from settings, never on launch. Unsupported web/desktop delivery is explained while the inbox remains available.

Android includes POST_NOTIFICATIONS, boot permission/receivers, a monochrome icon and Java desugaring. iOS configures the notification center delegate with explicit alert/sound permission requests.

## Verification and remaining limits

Final results are in NOTIFICATIONS_AND_UI_VERIFICATION.json. Tests cover persistence, migration, sample exclusion, quiet hours, daylight saving, denial, switches, sign-out, reset, account isolation, retry, app restart, barcode routing and draft preservation. UI tests include 320px width and 2× text in both themes; these also exposed and fixed date-range/weight-display overflow on Progress. Rendered previews are in output/previews/*-polished.png.

An earlier live Samsung SM S948B Android 16 test confirmed scheduled and immediate notifications in the OS tray while Kayleo was paused, using Asia/Kathmandu and reserved test IDs 9001/9002. The temporary verification folder disappeared between turns, so the implementation was restored into the persistent project and its checks rerun. The phone was disconnected during the final packaging session, so the final APK could not be installed or retested on-device. iPhone delivery has not been tested.

The existing PyTorch 2.1 native Android binaries are not natively 16 KB aligned. This remains a production dependency issue; a successful APK build does not resolve it. Official guidance: https://developer.android.com/guide/practices/page-sizes. Release-mode APKs use this project's existing debug/test signing key and are for local testing, not a production store release.

## Release toolchain fix

Flutter 3.47 regenerated GeneratedPluginRegistrant.java with the integration_test dev plugin during release compilation, even though Gradle correctly excluded the plugin from the release classpath. The Android build script removes only that generated test registration immediately before release Java compilation. Debug/integration registration is retained. This fixes the observed release javac error without including a test plugin in the production classpath. The hook becomes a no-op when Flutter generates the release registrant correctly.
