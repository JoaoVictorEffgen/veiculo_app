import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart';
import '../firebase/firestore_paths.dart';
import '../models/app_models.dart';
import 'vehicle_repository.dart';

class SeedUser {
  const SeedUser({required this.name, required this.email, required this.password, required this.role});

  final String name;
  final String email;
  final String password;
  final UserRole role;
}

class FirebaseVehicleRepository implements VehicleRepository {
  FirebaseVehicleRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AppUser? _cachedUser;

  static const _seedUsers = [
    SeedUser(name: 'Joao Silva', email: 'motorista1@empresa.com', password: '123456', role: UserRole.driver),
    SeedUser(name: 'Carlos Santos', email: 'motorista2@empresa.com', password: '123456', role: UserRole.driver),
    SeedUser(name: 'Marina Costa', email: 'motorista3@empresa.com', password: '123456', role: UserRole.driver),
    SeedUser(name: 'Pedro Oliveira', email: 'motorista4@empresa.com', password: '123456', role: UserRole.driver),
    SeedUser(name: 'Administrador', email: 'admin@empresa.com', password: '123456', role: UserRole.admin),
  ];

  static const _seedVehicles = [
    Vehicle(id: 'vehicle-1', name: 'Strada 01', model: 'Fiat Strada', plate: 'ABC-1D23', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
    Vehicle(id: 'vehicle-2', name: 'Toro 01', model: 'Fiat Toro', plate: 'DEF-4G56', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
    Vehicle(id: 'vehicle-3', name: 'Hilux', model: 'Toyota Hilux', plate: 'GHI-7J89', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
    Vehicle(id: 'vehicle-4', name: 'Saveiro', model: 'VW Saveiro', plate: 'JKL-0M12', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
    Vehicle(id: 'vehicle-5', name: 'Ranger', model: 'Ford Ranger', plate: 'MNO-3P45', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
    Vehicle(id: 'vehicle-6', name: 'Master', model: 'Renault Master', plate: 'PQR-6S78', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
    Vehicle(id: 'vehicle-7', name: 'Fiorino', model: 'Fiat Fiorino', plate: 'STU-9V01', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
  ];

  @override
  AppUser? get currentUser => _cachedUser;

  @override
  Stream<AppUser?> get authStateChanges async* {
    await for (final firebaseUser in _auth.authStateChanges()) {
      if (firebaseUser == null) {
        _cachedUser = null;
        yield null;
        continue;
      }
      _cachedUser = await _loadAppUser(firebaseUser.uid);
      yield _cachedUser;
    }
  }

  @override
  Future<String?> login(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      _cachedUser = await _loadAppUser(credential.user!.uid);
      if (_cachedUser == null) return 'Usuario sem cadastro no sistema.';
      return null;
    } on FirebaseAuthException catch (error) {
      return _authErrorMessage(error);
    }
  }

  @override
  Future<void> logout() async {
    await _auth.signOut();
    _cachedUser = null;
  }

  @override
  Stream<List<Vehicle>> watchVehicles() {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream.value(const <Vehicle>[]);
      return _firestore.collection(FirestorePaths.vehicles).orderBy('name').snapshots().map(
            (snapshot) => snapshot.docs.map(_vehicleFromDoc).toList(),
          );
    });
  }

  @override
  Future<List<Vehicle>> fetchVehicles() async {
    if (_auth.currentUser == null) return const [];
    final snapshot = await _firestore.collection(FirestorePaths.vehicles).orderBy('name').get();
    return snapshot.docs.map(_vehicleFromDoc).toList();
  }

  @override
  Stream<List<Movement>> watchMovements() {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream.value(const <Movement>[]);
      return _firestore.collection(FirestorePaths.movements).orderBy('createdAt', descending: true).snapshots().map(
            (snapshot) => snapshot.docs.map(_movementFromDoc).toList(),
          );
    });
  }

  @override
  Stream<List<AppUser>> watchUsers() {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream.value(const <AppUser>[]);
      return _firestore.collection(FirestorePaths.users).orderBy('name').snapshots().map(
            (snapshot) => snapshot.docs.map(_userFromDoc).toList(),
          );
    });
  }

  @override
  Future<String?> startVehicle(String vehicleId, AppUser user) async {
    final driverId = _auth.currentUser?.uid ?? user.id;
    try {
      await _firestore.runTransaction((transaction) async {
        final vehicleRef = _firestore.collection(FirestorePaths.vehicles).doc(vehicleId);
        final vehicleSnap = await transaction.get(vehicleRef);
        if (!vehicleSnap.exists) throw StateError('Veiculo nao encontrado.');
        final current = _vehicleFromDoc(vehicleSnap);
        if (current.status == VehicleStatus.moving) {
          final since = _formatTime(current.startedAt);
          throw StateError('Veiculo indisponivel: ${current.name} esta em uso por ${current.currentDriverName} desde $since.');
        }
        final now = Timestamp.now();
        transaction.update(vehicleRef, {
          'status': VehicleStatus.moving.name,
          'currentDriverId': driverId,
          'currentDriverName': user.name,
          'startedAt': now,
          'stoppedAt': FieldValue.delete(),
          'stoppedLocation': FieldValue.delete(),
        });
        final movementRef = _firestore.collection(FirestorePaths.movements).doc();
        transaction.set(movementRef, {
          'vehicleId': vehicleId,
          'vehicleName': current.name,
          'driverId': driverId,
          'driverName': user.name,
          'action': MovementAction.on.name,
          'createdAt': now,
          'location': null,
        });
      });
      return null;
    } on StateError catch (error) {
      return error.message;
    } on FirebaseException catch (error) {
      return error.message ?? 'Erro ao iniciar veiculo.';
    } catch (error) {
      return 'Erro ao iniciar veiculo: $error';
    }
  }

  @override
  Future<String?> stopVehicle(String vehicleId, AppUser user, String location) async {
    final driverId = _auth.currentUser?.uid ?? user.id;
    try {
      await _firestore.runTransaction((transaction) async {
        final vehicleRef = _firestore.collection(FirestorePaths.vehicles).doc(vehicleId);
        final vehicleSnap = await transaction.get(vehicleRef);
        if (!vehicleSnap.exists) throw StateError('Veiculo nao encontrado.');
        final current = _vehicleFromDoc(vehicleSnap);
        if (current.status == VehicleStatus.stopped) throw StateError('Este veiculo ja esta parado.');
        if (current.currentDriverId != driverId && user.role != UserRole.admin) {
          throw StateError('Somente o motorista responsavel pode parar o veiculo.');
        }
        final now = Timestamp.now();
        transaction.update(vehicleRef, {
          'status': VehicleStatus.stopped.name,
          'stoppedAt': now,
          'stoppedLocation': location.trim(),
        });
        final movementRef = _firestore.collection(FirestorePaths.movements).doc();
        transaction.set(movementRef, {
          'vehicleId': vehicleId,
          'vehicleName': current.name,
          'driverId': current.currentDriverId ?? driverId,
          'driverName': current.currentDriverName ?? user.name,
          'action': MovementAction.off.name,
          'createdAt': now,
          'location': location.trim(),
        });
      });
      return null;
    } on StateError catch (error) {
      return error.message;
    } on FirebaseException catch (error) {
      return error.message ?? 'Erro ao parar veiculo.';
    } catch (error) {
      return 'Erro ao parar veiculo: $error';
    }
  }

  @override
  Future<String?> addVehicle(AppUser actor, {required String name, required String model, required String plate}) async {
    if (actor.role != UserRole.admin) return 'Somente administradores podem alterar cadastros.';
    try {
      final id = 'vehicle-${DateTime.now().microsecondsSinceEpoch}';
      await _firestore.collection(FirestorePaths.vehicles).doc(id).set({
        'name': name.trim(),
        'model': model.trim(),
        'plate': plate.trim().toUpperCase(),
        'status': VehicleStatus.stopped.name,
        'currentDriverId': null,
        'currentDriverName': null,
        'startedAt': null,
        'stoppedAt': null,
        'stoppedLocation': 'Garagem da empresa',
      });
      return null;
    } on FirebaseException catch (error) {
      return error.message;
    }
  }

  @override
  Future<String?> editVehicle(AppUser actor, {required String vehicleId, required String name, required String model, required String plate}) async {
    if (actor.role != UserRole.admin) return 'Somente administradores podem alterar cadastros.';
    try {
      await _firestore.collection(FirestorePaths.vehicles).doc(vehicleId).update({
        'name': name.trim(),
        'model': model.trim(),
        'plate': plate.trim().toUpperCase(),
      });
      return null;
    } on FirebaseException catch (error) {
      return error.message;
    }
  }

  @override
  Future<String?> deleteVehicle(AppUser actor, String vehicleId) async {
    if (actor.role != UserRole.admin) return 'Somente administradores podem alterar cadastros.';
    try {
      final doc = await _firestore.collection(FirestorePaths.vehicles).doc(vehicleId).get();
      if (!doc.exists) return 'Veiculo nao encontrado.';
      final vehicle = _vehicleFromDoc(doc);
      if (vehicle.status == VehicleStatus.moving) return 'Nao e possivel excluir um veiculo em uso.';
      await doc.reference.delete();
      return null;
    } on FirebaseException catch (error) {
      return error.message;
    }
  }

  @override
  Future<String?> addDriver(AppUser actor, {required String name, required String email, required String password}) async {
    if (actor.role != UserRole.admin) return 'Somente administradores podem alterar cadastros.';
    try {
      final credential = await _createAuthUserWithoutSwitchingSession(email: email.trim().toLowerCase(), password: password);
      await _firestore.collection(FirestorePaths.users).doc(credential.user!.uid).set({
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'role': UserRole.driver.name,
      });
      return null;
    } on FirebaseAuthException catch (error) {
      return _authErrorMessage(error);
    } on FirebaseException catch (error) {
      return error.message;
    }
  }

  @override
  Future<String?> editDriver(AppUser actor, {required String driverId, required String name, required String email, required String password}) async {
    if (actor.role != UserRole.admin) return 'Somente administradores podem alterar cadastros.';
    try {
      await _firestore.collection(FirestorePaths.users).doc(driverId).update({
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
      });
      return null;
    } on FirebaseException catch (error) {
      return error.message;
    }
  }

  @override
  Future<String?> deleteDriver(AppUser actor, String driverId) async {
    if (actor.role != UserRole.admin) return 'Somente administradores podem alterar cadastros.';
    try {
      final vehicles = await _firestore.collection(FirestorePaths.vehicles).where('currentDriverId', isEqualTo: driverId).limit(1).get();
      if (vehicles.docs.isNotEmpty) return 'Nao e possivel excluir um motorista que esta usando um veiculo.';
      await _firestore.collection(FirestorePaths.users).doc(driverId).delete();
      return null;
    } on FirebaseException catch (error) {
      return error.message;
    }
  }

  @override
  Future<void> ensureSeedData() async {
    var adminExists = true;
    try {
      await _auth.signInWithEmailAndPassword(email: 'admin@empresa.com', password: '123456');
    } on FirebaseAuthException {
      adminExists = false;
      await _auth.signOut();
    }

    if (!adminExists) {
      for (final seed in _seedUsers) {
        await _ensureAuthUser(seed);
      }
      await _auth.signInWithEmailAndPassword(email: 'admin@empresa.com', password: '123456');
      await _seedVehiclesOnly();
      await _auth.signOut();
      return;
    }

    for (final seed in _seedUsers) {
      await _ensureAuthUser(seed);
    }

    final marker = await _firestore.collection(FirestorePaths.vehicles).doc('vehicle-1').get();
    if (!marker.exists) {
      await _seedVehiclesOnly();
    }

    await _auth.signOut();
  }

  Future<void> _ensureAuthUser(SeedUser seed) async {
    try {
      final credential = await _createAuthUserWithoutSwitchingSession(email: seed.email, password: seed.password);
      await _ensureUserDoc(credential.user!.uid, seed);
    } on FirebaseAuthException catch (error) {
      if (error.code != 'email-already-in-use') rethrow;
      final credential = await _signInWithoutSwitchingSession(email: seed.email, password: seed.password);
      await _ensureUserDoc(credential.user!.uid, seed);
    }
  }

  Future<void> _ensureUserDoc(String uid, SeedUser seed) async {
    final ref = _firestore.collection(FirestorePaths.users).doc(uid);
    final doc = await ref.get();
    if (doc.exists) return;
    await ref.set({
      'name': seed.name,
      'email': seed.email,
      'role': seed.role.name,
    });
  }

  Future<void> _seedVehiclesOnly() async {
    final batch = _firestore.batch();
    for (final vehicle in _seedVehicles) {
      batch.set(_firestore.collection(FirestorePaths.vehicles).doc(vehicle.id), _vehicleToMap(vehicle));
    }
    await batch.commit();
  }

  Future<UserCredential> _createAuthUserWithoutSwitchingSession({required String email, required String password}) async {
    final secondaryApp = await _createSecondaryApp();
    try {
      return await FirebaseAuth.instanceFor(app: secondaryApp).createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } finally {
      await secondaryApp.delete();
    }
  }

  Future<UserCredential> _signInWithoutSwitchingSession({required String email, required String password}) async {
    final secondaryApp = await _createSecondaryApp();
    try {
      return await FirebaseAuth.instanceFor(app: secondaryApp).signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } finally {
      await secondaryApp.delete();
    }
  }

  Future<FirebaseApp> _createSecondaryApp() {
    return Firebase.initializeApp(
      name: 'SecondaryAuth_${DateTime.now().microsecondsSinceEpoch}',
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  Future<AppUser?> _loadAppUser(String uid) async {
    final doc = await _firestore.collection(FirestorePaths.users).doc(uid).get();
    if (!doc.exists) return null;
    return _userFromDoc(doc);
  }

  AppUser _userFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return AppUser(
      id: doc.id,
      name: data['name'] as String,
      email: data['email'] as String,
      password: '',
      role: UserRole.values.byName(data['role'] as String),
    );
  }

  Vehicle _vehicleFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Vehicle(
      id: doc.id,
      name: data['name'] as String,
      model: data['model'] as String,
      plate: data['plate'] as String,
      status: VehicleStatus.values.byName(data['status'] as String),
      currentDriverId: data['currentDriverId'] as String?,
      currentDriverName: data['currentDriverName'] as String?,
      startedAt: (data['startedAt'] as Timestamp?)?.toDate(),
      stoppedAt: (data['stoppedAt'] as Timestamp?)?.toDate(),
      stoppedLocation: data['stoppedLocation'] as String?,
    );
  }

  Movement _movementFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Movement(
      id: doc.id,
      vehicleId: data['vehicleId'] as String,
      vehicleName: data['vehicleName'] as String,
      driverId: data['driverId'] as String,
      driverName: data['driverName'] as String,
      action: MovementAction.values.byName(data['action'] as String),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      location: data['location'] as String?,
    );
  }

  Map<String, dynamic> _vehicleToMap(Vehicle vehicle) => {
        'name': vehicle.name,
        'model': vehicle.model,
        'plate': vehicle.plate,
        'status': vehicle.status.name,
        'currentDriverId': vehicle.currentDriverId,
        'currentDriverName': vehicle.currentDriverName,
        'startedAt': vehicle.startedAt == null ? null : Timestamp.fromDate(vehicle.startedAt!),
        'stoppedAt': vehicle.stoppedAt == null ? null : Timestamp.fromDate(vehicle.stoppedAt!),
        'stoppedLocation': vehicle.stoppedLocation,
      };

  String _formatTime(DateTime? value) {
    if (value == null) return '--';
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _authErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-mail ou senha invalidos.';
      case 'email-already-in-use':
        return 'Ja existe um usuario com esse e-mail.';
      default:
        return error.message ?? 'Erro de autenticacao.';
    }
  }
}
