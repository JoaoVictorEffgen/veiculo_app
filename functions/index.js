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
        title: 'Nova tarefa da administracao',
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
        title: 'Resposta da tarefa',
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

exports.onDriverReportCreated = functions.firestore
  .document('driver_reports/{reportId}')
  .onCreate(async (snap) => {
    const data = snap.data();
    if (!data) return null;

    const tokens = await collectAdminTokens();
    if (tokens.length === 0) return null;

    const driverName = data.driverName || 'Motorista';
    const vehicleLabel = data.vehicleName ? ` • ${data.vehicleName}` : '';
    const body = (data.message || 'Novo relato recebido.').slice(0, 180);

    return admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: 'Novo relato de problema',
        body: `${driverName}${vehicleLabel}: ${body}`,
      },
      data: {
        type: 'driver_report',
        reportId: snap.id,
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'fleet_announcements',
        },
      },
    });
  });

exports.onDriverReportUpdated = functions.firestore
  .document('driver_reports/{reportId}')
  .onUpdate(async (change) => {
    const before = change.before.data();
    const after = change.after.data();
    if (!before || !after) return null;
    if (before.adminReply || !after.adminReply) return null;
    if (!after.driverId) return null;

    const tokens = await collectDriverTokens(after.driverId);
    if (tokens.length === 0) return null;

    const replyPreview = String(after.adminReply).slice(0, 180);

    return admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: 'Resposta ao seu relato',
        body: replyPreview,
      },
      data: {
        type: 'driver_report_reply',
        reportId: change.after.id,
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'fleet_announcements',
        },
      },
    });
  });

exports.adminSyncUserAuth = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Faca login como administrador.');
  }

  const targetUserId = String(data.targetUserId || '').trim();
  const newEmailRaw = data.newEmail;
  const newPasswordRaw = data.newPassword;

  if (!targetUserId) {
    throw new functions.https.HttpsError('invalid-argument', 'Motorista invalido.');
  }

  const db = admin.firestore();
  const callerDoc = await db.collection('users').doc(context.auth.uid).get();
  if (!callerDoc.exists || callerDoc.data().role !== 'admin') {
    throw new functions.https.HttpsError('permission-denied', 'Somente administradores.');
  }

  const callerCompanyId = callerDoc.data().companyId || 'default';
  const targetDoc = await db.collection('users').doc(targetUserId).get();
  if (!targetDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Usuario nao encontrado.');
  }

  const targetCompanyId = targetDoc.data().companyId || 'default';
  if (targetCompanyId !== callerCompanyId) {
    throw new functions.https.HttpsError('permission-denied', 'Motorista de outra empresa.');
  }

  const authUpdates = {};
  if (typeof newEmailRaw === 'string' && newEmailRaw.trim()) {
    authUpdates.email = newEmailRaw.trim().toLowerCase();
  }
  if (typeof newPasswordRaw === 'string' && newPasswordRaw.length > 0) {
    if (newPasswordRaw.length < 6) {
      throw new functions.https.HttpsError('invalid-argument', 'Senha com minimo 6 caracteres.');
    }
    authUpdates.password = newPasswordRaw;
  }

  if (Object.keys(authUpdates).length === 0) {
    return { updated: false };
  }

  await admin.auth().updateUser(targetUserId, authUpdates);
  return { updated: true };
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
