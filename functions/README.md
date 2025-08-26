This folder documents the expected Cloud Functions for user creation used by the Admin UI.

1) adminCreateUser (callable)
- Input: { email, password, role, displayName? }
- Output: { uid, email, role, displayName? }
- Behavior: Creates Firebase Auth user; sets custom claims { role } and optionally displayName; writes Firestore users/{uid} doc with { email, displayName, role, createdAt }.

2) adminBulkCreateUsers (callable)
- Input: { users: [{ email, password, role, displayName? }] }
- Output: { results: [{ email, uid, ok, error? }] }
- Behavior: Creates multiple users; for each success, sets claims and writes Firestore doc.

Security: Restrict callable to dev_admin or admin roles (verify via auth.token.role).
