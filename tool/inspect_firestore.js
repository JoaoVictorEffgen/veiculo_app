/**
 * Inspeciona colecoes do Firestore (somente leitura) e reporta duplicatas.
 *
 * Uso:
 *   node tool/inspect_firestore.js
 */
const admin = require('../functions/node_modules/firebase-admin');

const projectId = 'device-streaming-53bb0fb6';

async function listCollection(db, name, limit = 50) {
  const snap = await db.collection(name).limit(limit).get();
  return snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
}

async function main() {
  admin.initializeApp({ projectId });
  const db = admin.firestore();
  const auth = admin.auth();

  console.log(`Inspecao Firestore — projeto ${projectId}\n`);

  const vehicles = await listCollection(db, 'vehicles');
  const users = await listCollection(db, 'users');

  console.log(`Veiculos: ${vehicles.length}`);
  for (const v of vehicles) {
    console.log(`  - ${v.id}: ${v.name} (${v.plate}) status=${v.status}`);
  }

  console.log(`\nUsuarios Firestore: ${users.length}`);
  for (const u of users) {
    console.log(`  - ${u.id}: ${u.email} role=${u.role}`);
  }

  const byEmail = new Map();
  for (const u of users) {
    const email = (u.email || '').trim().toLowerCase();
    if (!email) continue;
    if (!byEmail.has(email)) byEmail.set(email, []);
    byEmail.get(email).push(u.id);
  }

  const dupes = [...byEmail.entries()].filter(([, ids]) => ids.length > 1);
  if (dupes.length) {
    console.log('\nDuplicatas por e-mail (Firestore):');
    for (const [email, ids] of dupes) {
      console.log(`  ${email}: ${ids.join(', ')}`);
    }
  } else {
    console.log('\nNenhuma duplicata por e-mail no Firestore.');
  }

  console.log('\nAuth (Firebase Authentication):');
  for (const email of [
    'admin@empresa.com',
    'motorista1@empresa.com',
    'motorista2@empresa.com',
    'motorista3@empresa.com',
    'motorista4@empresa.com',
  ]) {
    try {
      const user = await auth.getUserByEmail(email);
      const profile = users.find((u) => u.id === user.uid);
      const status = profile ? 'perfil OK' : 'SEM perfil Firestore';
      console.log(`  ${email} -> uid=${user.uid} (${status})`);
    } catch (error) {
      console.log(`  ${email} -> NAO EXISTE no Auth`);
    }
  }
}

main().catch((error) => {
  console.error('Falha na inspecao:', error.message || error);
  process.exit(1);
});
