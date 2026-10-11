# Communities and invite-only friends

Community replaces the previous local sample feed. It has 18 public circles: tracking beginners, fitness, weight loss, muscle gain, maintenance, keto, vegan, vegetarian, pescatarian, intermittent fasting, meal prep, walking, and 1,500/1,800/2,000/2,200/2,500/3,000 calorie circles. Calorie circles do not change personal targets.

## User flows

- Discover: search or filter circles, join, and open the conversation. My circles follows the account across devices.
- Chat: real-time messages, meal nutrition cards from recent/saved meals, daily check-in prompts, replies, cheers, author deletion, temporary hiding, and reports. Earlier messages load in pages of 100.
- Streaks: up to 100 members ordered by meal-logging streak, with shared ranks for ties and a pinned personal streak. Streaks reflect member logs and update while their app is active; this is not a verified competition.
- Challenge: a personal Monday–Sunday checklist derived from meal logs. A user participates by joining the circle; there is no separate fake enrollment count.
- Friends: each authenticated user receives a cryptographically random 96-bit invite code, a QR encoding the same capability, copy/share controls, and code replacement. Code possession explicitly grants an immediate mutual connection. No username search or member-profile action can create a friendship.
- Friend chat: private messages plus a Together tab comparing seven days of nutrition and logged activity minutes. Nutrition/activity sharing defaults off and is controlled independently. Turning a field off atomically removes its shared summaries. Name and logging streak are visible to friends; weight, meal notes, photos, and private diary records are excluded.
- Leaving a circle or removing a friend revokes future reads/writes on the server for both devices. Previously downloaded information cannot be recalled. Removing a friend does not rotate an invite; replace the code too if it should no longer work for that person.

## Data and authorization

`socialUsers/{uid}` is owner-only and contains the current invite code, joined circles, and sharing settings. `friendInvites/{code}` supports authenticated exact-document lookup and denies enumeration. Creating a friendship requires a valid current invite plus reciprocal friend edges in the same atomic operation. Friendship membership cannot be edited. Removing it atomically deletes both edges.

`communities/{id}/members/{uid}` contains display name, streak, and update timestamp. Public circle membership/streaks are visible to signed-in accounts. Messages and their cheers require active membership. `friendships/{pair}/messages` requires an active friendship. `socialProgress/{uid}` contains an explicitly shared seven-day summary, readable only by current friends and its owner. Private `users/{uid}/kayleoRecords` rules remain owner-only.

Social reports are write-only to clients and available to the Firebase project administrators. Reports do not automatically remove content, and there is no moderation dashboard or push-notification delivery in this change. Meal sharing currently supports nutrition cards and text; it does not upload photos.

The service follows the authenticated app session, debounces progress writes, skips sample diaries, updates at day rollover while active, and cancels subscriptions on sign-out/account switches. Network errors remain visible. Cached messages are labeled; sending waits for Firestore confirmation.

## Verification and deployment

```sh
rtk proxy flutter analyze
rtk proxy flutter test
rtk proxy flutter test test/community_test.dart --dart-define=CAPTURE_PREVIEWS=true
rtk proxy firebase emulators:exec --only auth,firestore --project demo-kayleo "cd tools/firebase_test && npm test"
rtk proxy firebase deploy --only firestore:rules --project kayleo-c9cca
```

The emulator tests cover owner-only diary access, private identity/code rules, invalid and missing invites, required reciprocal friendship creation, multi-account message delivery, opt-in sharing, invalidation of replaced codes, unfriend/leave revocation, message schemas, cheers, and reports. Widget tests cover discovery, QR rendering, chat actions, tie ranks, challenges, leaving, light/dark themes, and 320px screens at double text size.

Previews are under `output/previews/community-*.png`. Native camera permission, physical QR scanning, and cross-device behavior on installed release builds still need a two-device smoke test after rebuilding the app. Firebase rules deployment does not update the app already installed on a phone.

## Current verification status (October 11, 2026)

- Eight Firebase emulator tests passed.
- Thirteen community/accessibility checks passed, including friend comparison/removal and 320px room layouts at double text size.
- Release web compilation passed.
- The full suite reported 155 passes and 22 failures. An isolated copy with the original community and without the new social lifecycle hooks reproduced exactly the same 22 failing test names, confirming no new failures in that comparison.
- Production Firestore rules were **deployed successfully** to `kayleo-c9cca` after explicit user approval, using the already-signed-in project account `workwithkyaleo@gmail.com`. Firebase confirmed compilation, release to `cloud.firestore`, and deployment completion. The default CLI account lacked project access, so this command selected the authorized account without changing the global default.

Machine-readable results are in `docs/COMMUNITY_VERIFICATION.json`.
