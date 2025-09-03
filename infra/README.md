# Infra: Firebase Rules

This folder contains Cloud Firestore and Storage security rules tailored for this app.

Highlights:
- Firestore
  - Role-based access using Firebase Auth custom claims: `dev_admin`, `super_nodal`, `sub_nodal`, `project_owner`.
  - Users can read/write their own `users/{uid}` doc and `fcmTokens`.
  - Projects: owners CRUD their own; sub/super nodal can read by block; dev_admin full access.
  - Notifications: only the recipient can read/update (mark as read). Created by Cloud Functions.
  - Counters: `counters/projects` is open to authenticated clients for sequential code transaction; other counters/config are admin-only.
- Storage
  - Enforces content types and sizes: photos must be JPEG (<=7MB), videos MP4 (<=20MB), docs PDF or JPEG (<=20MB).
  - Client uploads must include customMetadata.uploaderId = current uid (the SDK sets this via `StorageService`), validated in rules.

Deploy
- firebase deploy --only storage,firestore:rules

Troubleshooting
- If uploads fail with permission-denied, ensure user is signed in and metadata `uploaderId` is present.
- If project code generation fails, confirm `counters/projects` exists or client has permission to create it.
