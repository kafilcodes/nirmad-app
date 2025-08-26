# Nirmad App

Production-grade Flutter app to track government construction projects.

Project context and requirements live in `.project_context/prd.md` and `.project_context/rules.md`.

## Setup
1. Copy `.env.template` to `.env` and fill Firebase web config (for web builds).
2. Ensure `android/app/google-services.json` is present (already added).
3. Run `flutter pub get`.
4. Run the app.

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
