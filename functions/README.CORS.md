# Cloud Functions callable setup for admin deletions

This project uses HTTPS callable functions to avoid CORS issues on Flutter Web.

Implement two callables in your Firebase Cloud Functions (Node 18, region `us-central1`):

- `adminDeleteUser` (onCall)
- `adminBulkDeleteUsers` (onCall)

Both should verify the caller has `dev_admin` (or your chosen claim), delete the Firebase Auth user, and delete the Firestore `users/{uid}` document. Optionally cascade delete related documents like projects.

Example TypeScript (ESM):

```ts
import * as functions from 'firebase-functions';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { initializeApp } from 'firebase-admin/app';

initializeApp();

export const adminDeleteUser = functions.region('us-central1').https.onCall(async (data, context) => {
  if (!context.auth?.token?.dev_admin) {
    throw new functions.https.HttpsError('permission-denied', 'Admins only');
  }
  const uid = String(data?.uid || '');
  if (!uid) throw new functions.https.HttpsError('invalid-argument', 'uid required');

  const auth = getAuth();
  const db = getFirestore();

  await auth.deleteUser(uid).catch(err => {
    if (err?.code !== 'auth/user-not-found') throw err;
  });

  const projSnap = await db.collection('projects').where('ownerId', '==', uid).get();
  const batch = db.batch();
  projSnap.docs.forEach(d => batch.delete(d.ref));
  batch.delete(db.collection('users').doc(uid));
  await batch.commit();

  return { ok: true };
});

export const adminBulkDeleteUsers = functions.region('us-central1').https.onCall(async (data, context) => {
  if (!context.auth?.token?.dev_admin) {
    throw new functions.https.HttpsError('permission-denied', 'Admins only');
  }
  const uids: string[] = Array.isArray(data?.uids) ? data.uids.map(String) : [];
  if (!uids.length) throw new functions.https.HttpsError('invalid-argument', 'uids required');

  const results: Array<{ uid: string; ok: boolean; error?: string }> = [];
  const auth = getAuth();
  const db = getFirestore();

  for (const uid of uids) {
    try {
      await auth.deleteUser(uid).catch(err => {
        if (err?.code !== 'auth/user-not-found') throw err;
      });
      const projSnap = await db.collection('projects').where('ownerId', '==', uid).get();
      const batch = db.batch();
      projSnap.docs.forEach(d => batch.delete(d.ref));
      batch.delete(db.collection('users').doc(uid));
      await batch.commit();
      results.push({ uid, ok: true });
    } catch (e: any) {
      results.push({ uid, ok: false, error: e?.message || String(e) });
    }
  }
  return results;
});
```

Deploy these with your existing Functions project. In Flutter, calls are already wired via `FunctionsService.adminDeleteUser` and `adminBulkDeleteUsers`.
