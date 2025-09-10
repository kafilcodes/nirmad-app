# Nirmad App

Production-grade Flutter app to track government construction projects.

### Nodal dashboard (recent)
- Role-scoped metrics and charts (fl_chart) for Super/Sub Nodal.
- Sub Nodal automatically filtered to assigned blocks.
- Projects tab supports grid/list toggle, basic status filter, and search box.
- Project details lets nodal officers send comments to owners (<= 300 chars), visible in updates and delivered as notifications.

Project context and requirements live in `.project_context/prd.md` and `.project_context/rules.md`.

## Setup
1. Copy `.env.template` to `.env` and fill Firebase web config (for web builds).
2. Ensure `android/app/google-services.json` is present (already added).
3. Run `flutter pub get`.
4. Run the app.

### .env keys
Add these keys to `.env` (values from Firebase Console):

```
# Firebase core (Web)
FIREBASE_API_KEY=
FIREBASE_PROJECT_ID=
FIREBASE_APP_ID=
FIREBASE_MESSAGING_SENDER_ID=
FIREBASE_AUTH_DOMAIN=
FIREBASE_STORAGE_BUCKET=
FIREBASE_MEASUREMENT_ID=

# FCM for Web
FCM_VAPID_KEY= # public VAPID key from Cloud Messaging > Web configuration
```

Note: Do not store any FCM private keys in the app or repo. Use server-side secrets for HTTP v1 sends.

## Infra
- Firestore rules: `infra/firestore.rules`
- Storage rules: `infra/storage.rules`
- Firebase config: `firebase.json`

## Cloud Functions

TypeScript functions live in `functions/`:
- `setUserClaims` (restricted to dev_admin) to set custom claims by user email and optional blocks.
- `exportProjectZip` to generate a ZIP (project.json, updates.json, and all project files) and return a signed URL.

Deploy:

```bash
cd functions
npm install
npm run deploy
```

Local emulators:

```bash
cd functions
npm run serve
```

## Notifications (FCM)

- Android: Runtime permission requested automatically on Android 13+. No extra console steps. Ensure Play Services present on device/emulator.
- Web: Set `FCM_VAPID_KEY` in `.env`. On first run, the browser will request notification permission. Ensure `web/firebase-messaging-sw.js` exists (added in this repo) so service worker registration succeeds. If you see "unsupported MIME type ('text/html')" in console, it means the service worker file was missing or not served at `/firebase-messaging-sw.js`.
- Tokens are stored at `users/{uid}/fcmTokens/{token}`.
- Add backend triggers to write `notifications` docs and send pushes as needed.

### Run on Web

```
flutter clean
flutter pub get
flutter run -d chrome
```

If hosting locally under a non-root path, keep `web/firebase-messaging-sw.js` at the site root or configure your dev server to serve it from `/firebase-messaging-sw.js`.
