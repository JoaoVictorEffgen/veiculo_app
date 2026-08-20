const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

async function collectDriverTokens(targetDriverId) {
  const db = admin.firestore();
  const tokens = [];

  if (targetDriverId) {
    const userDoc = await db.collection('users').doc(targetDriverId).get();
    const token = userDoc.exists ? userDoc.data().fcmToken : null;
    if (token) tokens.push(token);
    return tokens;
  }

  const drivers = await db.collection('users').where('role', '==', 'driver').get();
  drivers.forEach((doc) => {
    const token = doc.data().fcmToken;
    if (token) tokens.push(token);
  });
  return tokens;
}

async function collectAdminTokens() {
  const db = admin.firestore();
  const admins = await db.collection('users').where('role', '==', 'admin').get();
  const tokens = [];
  admins.forEach((doc) => {
    const token = doc.data().fcmToken;
    if (token) tokens.push(token);
  });
  return tokens;
}

exports.onAnnouncementCreated = functions.firestore
  .document('announcements/{announcementId}')
  .onCreate(async (snap) => {
    const data = snap.data();
    if (!data || data.active === false) return null;

    const tokens = await collectDriverTokens(data.targetDriverId || null);
    if (tokens.length === 0) return null;

    return admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: 'Novo lembrete da administracao',
        body: data.message || 'Voce recebeu um novo aviso.',
      },
      data: {
        type: 'announcement',
        announcementId: snap.id,
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'fleet_announcements',
        },
      },
    });
  });

exports.onAnnouncementUpdated = functions.firestore
  .document('announcements/{announcementId}')
  .onUpdate(async (change) => {
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return null;
    if (before.responseStatus || !after.responseStatus) return null;
    if (!after.targetDriverId) return null;

    const tokens = await collectAdminTokens();
    if (tokens.length === 0) return null;

    const driverName = after.respondedByName || after.targetDriverName || 'Motorista';
    const statusLabel = after.responseStatus === 'completed' ? 'concluiu' : 'recusou';

    return admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: 'Resposta do lembrete',
        body: `${driverName} ${statusLabel}: ${after.message || ''}`,
      },
      data: {
        type: 'announcement_response',
        announcementId: change.after.id,
        responseStatus: after.responseStatus,
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'fleet_announcements',
        },
      },
    });
  });

exports.purgeExpiredAnnouncements = functions.pubsub
  .schedule('every 15 minutes')
  .onRun(async () => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();
    const expired = await db.collection('announcements').where('expiresAt', '<=', now).get();

    if (expired.empty) return null;

    const batch = db.batch();
    expired.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    return null;
  });
