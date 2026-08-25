/**
 * Limpa todo o Firestore e recria usuarios/veiculos iniciais para testes.
 *
 * Uso (na raiz do projeto):
 *   node tool/reset_and_seed.js
 *
 * Requer: firebase login (firebase login) com acesso ao projeto.
 */
const admin = require('../functions/node_modules/firebase-admin');

const projectId = 'device-streaming-53bb0fb6';

const seedUsers = [
  { name: 'Joao Silva', email: 'motorista1@empresa.com', password: '123456', role: 'driver' },
  { name: 'Carlos Santos', email: 'motorista2@empresa.com', password: '123456', role: 'driver' },
  { name: 'Marina Costa', email: 'motorista3@empresa.com', password: '123456', role: 'driver' },
  { name: 'Pedro Oliveira', email: 'motorista4@empresa.com', password: '123456', role: 'driver' },
  { name: 'Administrador', email: 'admin@empresa.com', password: '123456', role: 'admin' },
];

const seedVehicles = [
  { id: 'vehicle-1', name: 'Strada 01', model: 'Fiat Strada', plate: 'ABC-1D23', status: 'stopped', stoppedLocation: 'Garagem da empresa' },
  { id: 'vehicle-2', name: 'Toro 01', model: 'Fiat Toro', plate: 'DEF-4G56', status: 'stopped', stoppedLocation: 'Garagem da empresa' },
  { id: 'vehicle-3', name: 'Hilux', model: 'Toyota Hilux', plate: 'GHI-7J89', status: 'stopped', stoppedLocation: 'Garagem da empresa' },
  { id: 'vehicle-4', name: 'Saveiro', model: 'VW Saveiro', plate: 'JKL-0M12', status: 'stopped', stoppedLocation: 'Garagem da empresa' },
  { id: 'vehicle-5', name: 'Ranger', model: 'Ford Ranger', plate: 'MNO-3P45', status: 'stopped', stoppedLocation: 'Garagem da empresa' },
  { id: 'vehicle-6', name: 'Master', model: 'Renault Master', plate: 'PQR-6S78', status: 'stopped', stoppedLocation: 'Garagem da empresa' },
  { id: 'vehicle-7', name: 'Fiorino', model: 'Fiat Fiorino', plate: 'STU-9V01', status: 'stopped', stoppedLocation: 'Garagem da empresa' },
];

const topCollections = [
  'users',
  'vehicles',
  'movements',
  'tracking',
  'announcements',
  'admin_alerts',
  'vehicle_checklists',
  'driver_reports',
];

async function deleteDocumentRecursive(docRef) {
  const subcollections = await docRef.listCollections();
  for (const sub of subcollections) {
    await deleteCollection(sub);
  }
  await docRef.delete();
}

async function deleteCollection(collectionRef) {
  while (true) {
    const snapshot = await collectionRef.limit(200).get();
    if (snapshot.empty) return;
    for (const doc of snapshot.docs) {
      await deleteDocumentRecursive(doc.ref);
    }
  }
}

async function wipeFirestore(db) {
  for (const name of topCollections) {
    console.log(`Apagando colecao ${name}...`);
    await deleteCollection(db.collection(name));
  }
}

async function ensureAuthUser(auth, user) {
  try {
    const existing = await auth.getUserByEmail(user.email);
    await auth.updateUser(existing.uid, { password: user.password, displayName: user.name });
    return existing.uid;
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
    const created = await auth.createUser({
      email: user.email,
      password: user.password,
      displayName: user.name,
    });
    return created.uid;
  }
}

async function seedFirestore(db, auth) {
  console.log('Recriando usuarios e veiculos iniciais...');
  for (const user of seedUsers) {
    const uid = await ensureAuthUser(auth, user);
    await db.collection('users').doc(uid).set({
      name: user.name,
      email: user.email,
      role: user.role,
    });
    console.log(`  usuario: ${user.email}`);
  }

  for (const vehicle of seedVehicles) {
    await db.collection('vehicles').doc(vehicle.id).set({
      name: vehicle.name,
      model: vehicle.model,
      plate: vehicle.plate,
      status: vehicle.status,
      stoppedLocation: vehicle.stoppedLocation,
    });
    console.log(`  veiculo: ${vehicle.name}`);
  }
}

async function main() {
  admin.initializeApp({ projectId });
  const db = admin.firestore();
  const auth = admin.auth();

  console.log(`Reset Firestore — projeto ${projectId}`);
  await wipeFirestore(db);
  await seedFirestore(db, auth);
  console.log('Banco limpo e seed aplicado. Pode testar do zero.');
  console.log('Login: admin@empresa.com / motorista1@empresa.com — senha 123456');
}

main().catch((error) => {
  console.error('Falha no reset:', error);
  process.exit(1);
});
