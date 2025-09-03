import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue, QueryDocumentSnapshot } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { getStorage } from 'firebase-admin/storage';
import * as functions from 'firebase-functions';
import archiver from 'archiver';
import tmp from 'tmp';

initializeApp();
const auth = getAuth();
const db = getFirestore();
const storage = getStorage();
const fcm = getMessaging();

const WHITELISTED_UIDS = new Set<string>([
  'IckVUW6Mg4Ue1XNcVWsxTidSiBY2',
]);
const WHITELISTED_EMAILS = new Set<string>([
  'kafilcodes@gmail.com',
]);

function isSuperCaller(user: import('firebase-admin/auth').UserRecord): boolean {
  const claims = (user.customClaims || {}) as any;
  const email = user.email?.toLowerCase();
  return (
    claims.role === 'dev_admin' ||
    WHITELISTED_UIDS.has(user.uid) ||
    (email != null && WHITELISTED_EMAILS.has(email))
  );
}

export const setUserClaims = functions.https.onCall(async (
  data: { email?: string; role?: string; blocks?: string[] },
  context: functions.https.CallableContext,
) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Auth required');
  }
  const callerToken = await auth.getUser(context.auth.uid);
  if (!isSuperCaller(callerToken)) {
    throw new functions.https.HttpsError('permission-denied', 'Dev admin only');
  }
  const email: string | undefined = data.email;
  const role: string | undefined = data.role;
  const blocks: string[] | undefined = data.blocks;
  if (!email || !role) {
    throw new functions.https.HttpsError('invalid-argument', 'email and role are required');
  }
  const user = await auth.getUserByEmail(email);
  const claims: Record<string, unknown> = { role };
  if (blocks) claims['blocks'] = blocks;
  await auth.setCustomUserClaims(user.uid, claims);
  await db.collection('users').doc(user.uid).set({ email, role, blocks: blocks ?? [] }, { merge: true });
  return { ok: true };
});

export const exportProjectZip = functions.https.onCall(async (
  data: { projectId?: string },
  context: functions.https.CallableContext,
) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Auth required');
  }
  const projectId: string | undefined = data.projectId;
  if (!projectId) {
    throw new functions.https.HttpsError('invalid-argument', 'projectId required');
  }

  // Permission check: allow dev_admin, super_nodal, sub_nodal, or project owner
  const user = await auth.getUser(context.auth.uid);
  const claims = (user.customClaims || {}) as any;

  const projectRef = db.collection('projects').doc(projectId);
  const projectSnap = await projectRef.get();
  if (!projectSnap.exists) throw new functions.https.HttpsError('not-found', 'Project missing');
  const project = projectSnap.data() as any;

  const role: string | undefined = claims.role;
  if (role === 'project_owner' && project.ownerId !== user.uid) {
    throw new functions.https.HttpsError('permission-denied', 'Not your project');
  }
  if (role === 'sub_nodal') {
    const blocks: string[] = claims.blocks || [];
    if (!blocks.includes(project.blockId)) {
      throw new functions.https.HttpsError('permission-denied', 'Block mismatch');
    }
  }

  const output = storage.bucket().file(`exports/${projectId}-${Date.now()}.zip`);

  const passthrough = output.createWriteStream({
    contentType: 'application/zip',
    resumable: false,
    metadata: { cacheControl: 'no-cache' },
  });

  const archive = archiver('zip', { zlib: { level: 9 } });
  archive.on('warning', (err: unknown) => functions.logger.warn('archive warn', err as any));
  archive.on('error', (err: Error) => { throw err; });

  // Collect Firestore data
  const updatesSnap = await projectRef.collection('updates').orderBy('createdAt').get();
  const projectJson = JSON.stringify({ id: projectId, ...project }, null, 2);
  const updatesJson = JSON.stringify(updatesSnap.docs.map((d: QueryDocumentSnapshot) => ({ id: d.id, ...d.data() })), null, 2);
  archive.append(projectJson, { name: 'project.json' });
  archive.append(updatesJson, { name: 'updates.json' });

  // Collect files from Storage under projects/{id}/
  const bucket = storage.bucket();
  const [files] = await bucket.getFiles({ prefix: `projects/${projectId}/` });
  for (const f of files) {
    const stream = f.createReadStream();
    archive.append(stream, { name: f.name.replace(`projects/${projectId}/`, '') || f.name });
  }

  archive.finalize();
  const piping = new Promise<void>((resolve, reject) => {
    archive.pipe(passthrough)
      .on('finish', () => resolve())
      .on('error', (e: Error) => reject(e));
  });
  await piping;

  // Get signed URL
  const [url] = await output.getSignedUrl({ action: 'read', expires: Date.now() + 1000 * 60 * 10 });
  return url;
});

export const seedTestUsers = functions.https.onCall(async (
  data: { owners?: number; nodals?: number; domain?: string; blockIds?: string[] },
  context: functions.https.CallableContext,
) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Auth required');
  const user = await auth.getUser(context.auth.uid);
  const claims = (user.customClaims || {}) as any;
  if (claims.role !== 'dev_admin') throw new functions.https.HttpsError('permission-denied', 'Dev admin only');

  const owners = Math.max(0, Math.min(100, data.owners ?? 5));
  const nodals = Math.max(0, Math.min(20, data.nodals ?? 2));
  const domain = data.domain || 'example.com';
  const blockIds = data.blockIds || ['block-a', 'block-b'];

  const creds: { email: string; password: string; role: string; blocks?: string[] }[] = [];
  for (let i = 1; i <= owners; i++) {
    creds.push({ email: `owner${i}@${domain}`, password: 'Passw0rd!', role: 'project_owner' });
  }
  for (let i = 1; i <= nodals; i++) {
    creds.push({ email: `nodal${i}@${domain}`, password: 'Passw0rd!', role: 'sub_nodal', blocks: blockIds });
  }

  const results: any[] = [];
  for (const c of creds) {
    try {
  const created = await auth.createUser({ email: c.email, password: c.password, emailVerified: false, displayName: c.email.split('@')[0] });
  await auth.setCustomUserClaims(created.uid, { role: c.role, blocks: c.blocks ?? [] });
  await db.collection('users').doc(created.uid).set({ email: c.email, role: c.role, blocks: c.blocks ?? [] }, { merge: true });
      results.push({ email: c.email, password: c.password, ok: true });
    } catch (e: any) {
      results.push({ email: c.email, error: e?.message || String(e) });
    }
  }
  return { results };
});

export const bootstrapDevAdmin = functions.https.onCall(async (
  data: { email?: string; password?: string },
  _context: functions.https.CallableContext,
) => {
  const cfgRef = db.collection('config').doc('bootstrap');
  const cfgSnap = await cfgRef.get();
  if (cfgSnap.exists && (cfgSnap.data() as any)?.used === true) {
    throw new functions.https.HttpsError('failed-precondition', 'Bootstrap already used');
  }
  const email = data.email?.trim();
  const password = data.password;
  if (!email || !password) {
    throw new functions.https.HttpsError('invalid-argument', 'email and password required');
  }
  // Create user and set claims
  let userRecord: import('firebase-admin/auth').UserRecord;
  try {
    userRecord = await auth.createUser({ email, password, emailVerified: false, displayName: 'Dev Admin' });
  } catch (e: any) {
    // If exists, fetch it
    if (e?.code === 'auth/email-already-exists') {
      userRecord = await auth.getUserByEmail(email);
    } else {
      throw new functions.https.HttpsError('internal', e?.message || String(e));
    }
  }
  await auth.setCustomUserClaims(userRecord.uid, { role: 'dev_admin' });
  await db.collection('users').doc(userRecord.uid).set({ email, role: 'dev_admin', blocks: [] }, { merge: true });
  await cfgRef.set({ used: true, at: FieldValue.serverTimestamp(), adminEmail: email }, { merge: true });
  return { ok: true, email };
});

// Creates a single Firebase Auth user, sets claims and writes Firestore user doc
export const adminCreateUser = functions.https.onCall(async (
  data: { email?: string; password?: string; role?: string; displayName?: string },
  context: functions.https.CallableContext,
) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Auth required');
  const caller = await auth.getUser(context.auth.uid);
  if (!isSuperCaller(caller)) throw new functions.https.HttpsError('permission-denied', 'Dev admin only');

  const email = data.email?.trim();
  const password = data.password;
  const role = (data.role || 'project_owner').trim();
  const displayName = data.displayName?.trim();
  if (!email || !password) throw new functions.https.HttpsError('invalid-argument', 'email and password required');

  let userRecord: import('firebase-admin/auth').UserRecord;
  try {
    userRecord = await auth.createUser({ email, password, emailVerified: false, displayName });
  } catch (e: any) {
    if (e?.code === 'auth/email-already-exists') {
      userRecord = await auth.getUserByEmail(email);
    } else {
      throw new functions.https.HttpsError('internal', e?.message || String(e));
    }
  }
  await auth.setCustomUserClaims(userRecord.uid, { role });
  await db.collection('users').doc(userRecord.uid).set({ email, role, ...(displayName ? { displayName } : {}), createdAt: FieldValue.serverTimestamp() }, { merge: true });
  return { uid: userRecord.uid, email, role, displayName };
});

// Bulk create many users
export const adminBulkCreateUsers = functions.https.onCall(async (
  data: { users?: { email?: string; password?: string; role?: string; displayName?: string }[] },
  context: functions.https.CallableContext,
) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Auth required');
  const caller = await auth.getUser(context.auth.uid);
  if (!isSuperCaller(caller)) throw new functions.https.HttpsError('permission-denied', 'Dev admin only');
  const users = data.users || [];
  const results: { email: string; uid?: string; ok: boolean; error?: string }[] = [];
  for (const u of users) {
    const email = u.email?.trim();
    const password = u.password;
    const role = (u.role || 'project_owner').trim();
    const displayName = u.displayName?.trim();
    if (!email || !password) {
      results.push({ email: email || '', ok: false, error: 'missing email/password' });
      continue;
    }
    try {
      let userRecord: import('firebase-admin/auth').UserRecord;
      try {
        userRecord = await auth.createUser({ email, password, emailVerified: false, displayName });
      } catch (e: any) {
        if (e?.code === 'auth/email-already-exists') {
          userRecord = await auth.getUserByEmail(email);
        } else {
          throw e;
        }
      }
      await auth.setCustomUserClaims(userRecord.uid, { role });
      await db.collection('users').doc(userRecord.uid).set({ email, role, ...(displayName ? { displayName } : {}), createdAt: FieldValue.serverTimestamp() }, { merge: true });
      results.push({ email, uid: userRecord.uid, ok: true });
    } catch (e: any) {
      results.push({ email, ok: false, error: e?.message || String(e) });
    }
  }
  return { results };
});

// Delete a single user from Firebase Auth and Firestore (plus cascade example: projects)
export const adminDeleteUser = functions.https.onCall(async (
  data: { uid?: string },
  context: functions.https.CallableContext,
) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Auth required');
  const caller = await auth.getUser(context.auth.uid);
  if (!isSuperCaller(caller)) throw new functions.https.HttpsError('permission-denied', 'Dev admin only');

  const uid = (data.uid || '').trim();
  if (!uid) throw new functions.https.HttpsError('invalid-argument', 'uid required');

  // Delete from Firebase Auth (ignore if already gone)
  await auth.deleteUser(uid).catch((e: any) => {
    if (e?.code !== 'auth/user-not-found') throw new functions.https.HttpsError('internal', e?.message || String(e));
  });

  // Delete related Firestore data (example cascade: projects by owner)
  const projSnap = await db.collection('projects').where('ownerId', '==', uid).get();
  const batch = db.batch();
  for (const doc of projSnap.docs) {
    batch.delete(doc.ref);
  }
  batch.delete(db.collection('users').doc(uid));
  await batch.commit();

  return { ok: true };
});

// Bulk delete many users; returns per-uid status
export const adminBulkDeleteUsers = functions.https.onCall(async (
  data: { uids?: string[] },
  context: functions.https.CallableContext,
) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Auth required');
  const caller = await auth.getUser(context.auth.uid);
  if (!isSuperCaller(caller)) throw new functions.https.HttpsError('permission-denied', 'Dev admin only');

  const uids = Array.isArray(data.uids) ? data.uids.map((u) => String(u).trim()).filter(Boolean) : [];
  if (uids.length === 0) throw new functions.https.HttpsError('invalid-argument', 'uids required');

  const results: Array<{ uid: string; ok: boolean; error?: string }> = [];
  for (const uid of uids) {
    try {
      await auth.deleteUser(uid).catch((e: any) => {
        if (e?.code !== 'auth/user-not-found') throw e;
      });
      const projSnap = await db.collection('projects').where('ownerId', '==', uid).get();
      const batch = db.batch();
      for (const doc of projSnap.docs) batch.delete(doc.ref);
      batch.delete(db.collection('users').doc(uid));
      await batch.commit();
      results.push({ uid, ok: true });
    } catch (e: any) {
      results.push({ uid, ok: false, error: e?.message || String(e) });
    }
  }
  // Return as an array (client supports array or {results})
  return results;
});

// Ensure the currently signed-in whitelisted user is promoted to dev_admin (one-time helper)
export const ensureDevAdminForWhitelisted = functions.https.onCall(async (
  _data: Record<string, unknown>,
  context: functions.https.CallableContext,
) => {
  if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Auth required');
  const me = await auth.getUser(context.auth.uid);
  // Only allow if caller is in whitelist
  const email = me.email?.toLowerCase();
  const whitelisted = WHITELISTED_UIDS.has(me.uid) || (email != null && WHITELISTED_EMAILS.has(email));
  if (!whitelisted) throw new functions.https.HttpsError('permission-denied', 'Not whitelisted');
  await auth.setCustomUserClaims(me.uid, { role: 'dev_admin' });
  await db.collection('users').doc(me.uid).set({ email: me.email, role: 'dev_admin', blocks: [] }, { merge: true });
  return { ok: true };
});

// --- Notifications helpers ---
type AppUser = { email?: string; role?: string; blocks?: string[] };

async function getUsersByRole(role: string, blocks?: string[]): Promise<Array<{ id: string; data: AppUser }>> {
  let q = db.collection('users').where('role', '==', role) as FirebaseFirestore.Query<FirebaseFirestore.DocumentData>;
  if (blocks && blocks.length > 0 && role === 'sub_nodal') {
    // sub_nodal must include at least one of the blocks
    q = q.where('blocks', 'array-contains-any', blocks.slice(0, 10));
  }
  const snap = await q.get();
  return snap.docs.map(d => ({ id: d.id, data: d.data() as AppUser }));
}

async function createNotificationDoc(toUserId: string, payload: { title: string; body: string; data?: Record<string, string> }) {
  await db.collection('notifications').add({
    userId: toUserId,
    title: payload.title,
    body: payload.body,
    data: payload.data || {},
    createdAt: FieldValue.serverTimestamp(),
    readAt: null,
  });
}

async function sendToUserTokens(userId: string, payload: { title: string; body: string; data?: Record<string, string> }) {
  const tokensSnap = await db.collection('users').doc(userId).collection('fcmTokens').get();
  if (tokensSnap.empty) return;
  const tokens = tokensSnap.docs.map(d => d.id);
  const message = {
    notification: { title: payload.title, body: payload.body },
    webpush: { headers: { Urgency: 'normal' } },
    data: payload.data || {},
    tokens,
  } as any;
  const resp = await fcm.sendEachForMulticast(message);
  // Clean up invalid tokens
  const invalidIdx = resp.responses.map((r, i) => (!r.success ? i : -1)).filter(i => i >= 0);
  const toDelete = invalidIdx.map(i => tokens[i]);
  if (toDelete.length > 0) {
    const batch = db.batch();
    toDelete.forEach(t => batch.delete(db.collection('users').doc(userId).collection('fcmTokens').doc(t)));
    await batch.commit();
  }
}

async function notifyUsers(userIds: string[], payload: { title: string; body: string; data?: Record<string, string> }) {
  await Promise.all(userIds.map(async (uid) => {
    await createNotificationDoc(uid, payload);
    await sendToUserTokens(uid, payload).catch((e) => functions.logger.warn('FCM send error', uid, e));
  }));
}

// Trigger notifications on project create/update
export const onProjectWrite = functions.region('us-central1').firestore
  .document('projects/{projectId}')
  .onWrite(async (change, context) => {
    const projectId = context.params.projectId as string;
    const after = change.after.exists ? change.after.data() as any : null;
    const before = change.before.exists ? change.before.data() as any : null;

    if (!after && before) {
      // Deleted: notify super_nodal
      const supers = await getUsersByRole('super_nodal');
      const msg = { title: 'Project deleted', body: `Project ${projectId} was deleted`, data: { projectId } };
      await notifyUsers(supers.map(u => u.id), msg);
      return;
    }
    if (!after) return;

    const name = after.name || projectId;
    const blockId = after.blockId as string | undefined;
    const ownerId = after.ownerId as string | undefined;
    const status = after.status as string | undefined;

    // Determine action
    const created = !before;
    const statusChanged = before && after && before.status !== after.status;

    const targets: Set<string> = new Set();
    // Super nodals always get notified
    const supers = await getUsersByRole('super_nodal');
    supers.forEach(u => targets.add(u.id));
    // Sub nodals in same block get notified
    if (blockId) {
      const subs = await getUsersByRole('sub_nodal', [blockId]);
      subs.forEach(u => targets.add(u.id));
    }
    // Owner gets notified too
    if (ownerId) targets.add(ownerId);

    let title = 'Project updated';
    let body = `${name} updated`;
    if (created) {
      title = 'New project created';
      body = `${name} created`;
    } else if (statusChanged) {
      title = 'Project status changed';
      body = `${name} is now ${status}`;
    }
    const data: Record<string, string> = { projectId, ...(status ? { status: String(status) } : {}) };
    await notifyUsers(Array.from(targets), { title, body, data });
  });
