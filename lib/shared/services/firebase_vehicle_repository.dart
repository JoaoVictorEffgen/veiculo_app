import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import '../firebase/firestore_paths.dart';
import '../models/app_models.dart';
import '../seed/app_seed_data.dart';
import 'vehicle_repository.dart';

class FirebaseVehicleRepository implements VehicleRepository {
  FirebaseVehicleRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AppUser? _cachedUser;

  static const _seedUsers = AppSeedData.users;
  static const _seedVehicles = AppSeedData.vehicles;

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

      if (_cachedUser?.id == firebaseUser.uid) {
        yield _cachedUser;
      }

      final loaded = await _loadAppUser(firebaseUser.uid);
      _cachedUser = loaded;
      yield loaded;
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
  Future<String?> sendPasswordResetEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return 'Informe o e-mail da sua conta.';

    try {
      await _auth.sendPasswordResetEmail(email: normalized);
      return null;
    } on FirebaseAuthException catch (error) {
      switch (error.code) {
        case 'invalid-email':
          return 'Informe um e-mail valido.';
        case 'too-many-requests':
          return 'Muitas tentativas. Aguarde alguns minutos e tente novamente.';
        default:
          return error.message ?? 'Nao foi possivel enviar o e-mail de recuperacao.';
      }
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
    return _auth.authStateChanges().asyncExpand((user) async* {
      if (user == null) {
        yield const <Movement>[];
        return;
      }
      final appUser = _cachedUser ?? await _loadAppUser(user.uid);
      final query = appUser?.role == UserRole.admin
          ? _firestore.collection(FirestorePaths.movements).orderBy('createdAt', descending: true)
          : _firestore
              .collection(FirestorePaths.movements)
              .where('driverId', isEqualTo: user.uid)
              .orderBy('createdAt', descending: true);
      yield* query.snapshots().map((snapshot) => snapshot.docs.map(_movementFromDoc).toList());
    });
  }

  @override
  Stream<List<AppUser>> watchUsers() {
    return _auth.authStateChanges().asyncExpand((user) async* {
      if (user == null) {
        yield const <AppUser>[];
        return;
      }
      final appUser = _cachedUser ?? await _loadAppUser(user.uid);
      if (appUser?.role == UserRole.admin) {
        yield* _firestore.collection(FirestorePaths.users).orderBy('name').snapshots().map(
              (snapshot) => snapshot.docs.map(_userFromDoc).toList(),
            );
        return;
      }
      yield* _firestore.collection(FirestorePaths.users).doc(user.uid).snapshots().map(
            (snapshot) => snapshot.exists ? [_userFromDoc(snapshot)] : const <AppUser>[],
          );
    });
  }

  @override
  Stream<List<DriverTrack>> watchDriverTracks() {
    return _auth.authStateChanges().asyncExpand((user) async* {
      if (user == null) {
        yield const <DriverTrack>[];
        return;
      }
      final appUser = _cachedUser ?? await _loadAppUser(user.uid);
      if (appUser?.role == UserRole.admin) {
        yield* _firestore.collection(FirestorePaths.tracking).snapshots().map(
              (snapshot) => snapshot.docs.map(_trackFromDoc).toList(),
            );
        return;
      }
      yield* _firestore.collection(FirestorePaths.tracking).doc(user.uid).snapshots().map(
            (snapshot) => snapshot.exists ? [_trackFromDoc(snapshot)] : const <DriverTrack>[],
          );
    });
  }

  @override
  Stream<List<FleetAnnouncement>> watchAnnouncementsForUser(AppUser user) {
    return _auth.authStateChanges().asyncExpand((authUser) {
      if (authUser == null) return Stream.value(const <FleetAnnouncement>[]);

      return _firestore
          .collection(FirestorePaths.announcements)
          .where('active', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .asyncMap((snapshot) async {
        final announcements = snapshot.docs.map(_announcementFromDoc).where((item) => item.isVisibleTo(user)).toList();

        final expiredIds = snapshot.docs
            .map(_announcementFromDoc)
            .where((item) => item.isExpired)
            .map((item) => item.id)
            .toList();
        if (expiredIds.isNotEmpty) {
          unawaited(_deleteExpiredAnnouncements(expiredIds));
        }

        return announcements.where((item) => !item.isExpired).toList();
      });
    });
  }

  Future<void> _deleteExpiredAnnouncements(List<String> ids) async {
    for (final id in ids) {
      try {
        await _firestore.collection(FirestorePaths.announcements).doc(id).delete();
      } on FirebaseException catch (error) {
        debugPrint('Falha ao remover tarefa expirada $id: ${error.message}');
      }
    }
  }

  @override
  Future<String?> publishAnnouncement(
    AppUser actor, {
    required String message,
    DateTime? expiresAt,
    String? targetDriverId,
    String? targetDriverName,
  }) async {
    if (actor.role != UserRole.admin) return 'Somente administradores podem publicar tarefas.';
    final text = message.trim();
    if (text.isEmpty) return 'Escreva a tarefa antes de publicar.';
    if (expiresAt != null && !expiresAt.isAfter(DateTime.now())) {
      return 'A data de validade precisa ser futura.';
    }

    try {
      await _firestore.collection(FirestorePaths.announcements).add({
        'message': text,
        'createdAt': FieldValue.serverTimestamp(),
        'createdById': actor.id,
        'createdByName': actor.name,
        'active': true,
        if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
        if (targetDriverId != null) 'targetDriverId': targetDriverId,
        if (targetDriverName != null) 'targetDriverName': targetDriverName,
      });
      return null;
    } on FirebaseException catch (error) {
      return error.message ?? 'Erro ao publicar tarefa.';
    }
  }

  @override
  Future<String?> deleteAnnouncement(AppUser actor, String announcementId) async {
    if (actor.role != UserRole.admin) return 'Somente administradores podem remover tarefas.';

    try {
      await _firestore.collection(FirestorePaths.announcements).doc(announcementId).delete();
      return null;
    } on FirebaseException catch (error) {
      return error.message ?? 'Erro ao remover tarefa.';
    }
  }

  @override
  Future<String?> respondToAnnouncement(
    AppUser driver,
    String announcementId,
    AnnouncementResponseStatus status, {
    String? rejectionReason,
  }) async {
    if (driver.role != UserRole.driver) return 'Somente motoristas podem responder tarefas.';
    if (status == AnnouncementResponseStatus.rejected &&
        (rejectionReason == null || rejectionReason.trim().isEmpty)) {
      return 'Informe a justificativa para recusar a tarefa.';
    }

    try {
      final authUid = _auth.currentUser?.uid;
      if (authUid == null) return 'Sessao expirada. Faca login novamente.';
      if (authUid != driver.id) return 'Sessao invalida. Faca login novamente.';

      await _firestore.runTransaction((transaction) async {
        final docRef = _firestore.collection(FirestorePaths.announcements).doc(announcementId);
        final doc = await transaction.get(docRef);
        if (!doc.exists) {
          throw StateError('Tarefa ja foi concluida por outro motorista.');
        }

        final announcement = _announcementFromDoc(doc);
        if (announcement.isExpired) throw StateError('Esta tarefa expirou.');

        if (announcement.isGroupTask) {
          if (status != AnnouncementResponseStatus.completed) {
            throw StateError('Tarefas para todos so podem ser concluidas.');
          }
        } else if (announcement.targetDriverId != driver.id) {
          throw StateError('Esta tarefa nao foi destinada a voce.');
        }

        if (!announcement.isPendingResponse) {
          throw StateError('Esta tarefa ja foi respondida.');
        }

        final alertRef = _firestore.collection(FirestorePaths.adminAlerts).doc();
        transaction.set(alertRef, {
          'announcementId': announcementId,
          'driverId': authUid,
          'driverName': driver.name,
          'message': announcement.message,
          'responseStatus': status.name,
          'isGroupTask': announcement.isGroupTask,
          if (status == AnnouncementResponseStatus.rejected) 'rejectionReason': rejectionReason!.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'viewed': false,
        });

        transaction.update(docRef, {
          'active': false,
          'responseStatus': status.name,
          'respondedAt': FieldValue.serverTimestamp(),
          'respondedByName': driver.name,
          if (status == AnnouncementResponseStatus.rejected) 'rejectionReason': rejectionReason!.trim(),
        });
      });
      return null;
    } on StateError catch (error) {
      return error.message;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return 'Sem permissao para concluir a tarefa. Tente sair e entrar novamente.';
      }
      return error.message ?? 'Erro ao responder tarefa.';
    }
  }

  @override
  Stream<List<FleetAdminAlert>> watchAdminAlerts() {
    return _auth.authStateChanges().asyncExpand((user) {
      if (user == null) return Stream.value(const <FleetAdminAlert>[]);
      return _firestore
          .collection(FirestorePaths.adminAlerts)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs.map(_adminAlertFromDoc).toList());
    });
  }

  @override
  Future<void> markAdminAlertsViewed(AppUser admin) async {
    if (admin.role != UserRole.admin) return;

    final unread = await _firestore
        .collection(FirestorePaths.adminAlerts)
        .where('viewed', isEqualTo: false)
        .get();

    if (unread.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {
        'viewed': true,
        'viewedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  @override
  Future<void> saveFcmToken(AppUser user, String token) async {
    try {
      await _firestore.collection(FirestorePaths.users).doc(user.id).set(
        {
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on FirebaseException catch (error) {
      debugPrint('Falha ao salvar token FCM: ${error.message}');
    }
  }

  @override
  Future<VehicleChecklist?> getTodayChecklist(AppUser driver, String vehicleId) async {
    if (!driver.mustCompleteVehicleChecklist) return null;

    final docId = vehicleChecklistDocId(driverId: driver.id, vehicleId: vehicleId);
    final docRef = _firestore.collection(FirestorePaths.vehicleChecklists).doc(docId);

    try {
      final cached = await docRef
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(milliseconds: 400));
      if (cached.exists) return _checklistFromDoc(cached);
    } catch (_) {}

    try {
      final remote = await docRef.get().timeout(const Duration(seconds: 4));
      if (remote.exists) return _checklistFromDoc(remote);
    } catch (error) {
      debugPrint('getTodayChecklist: $error');
    }
    return null;
  }

  @override
  Stream<List<VehicleChecklist>> watchTodayChecklistsForDriver(AppUser driver) {
    if (!driver.mustCompleteVehicleChecklist) return Stream.value(const <VehicleChecklist>[]);

    return _firestore
        .collection(FirestorePaths.vehicleChecklists)
        .where('driverId', isEqualTo: driver.id)
        .where('checklistDate', isEqualTo: checklistDateKey())
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_checklistFromDoc).toList());
  }

  @override
  Future<String?> saveVehicleChecklist(
    AppUser driver,
    Vehicle vehicle, {
    required Map<String, bool> items,
    String? notes,
    required String signatureBase64,
  }) async {
    if (!driver.mustCompleteVehicleChecklist) {
      return 'Somente motoristas e administradores podem registrar checklist.';
    }

    final authUser = _auth.currentUser;
    if (authUser == null) return 'Sessao expirada. Faca login novamente.';
    if (authUser.uid != driver.id) return 'Sessao invalida. Faca login novamente.';

    if (signatureBase64.trim().isEmpty) return 'Assine o checklist antes de concluir.';

    final docId = vehicleChecklistDocId(driverId: driver.id, vehicleId: vehicle.id);
    final docRef = _firestore.collection(FirestorePaths.vehicleChecklists).doc(docId);
    final itemMap = {for (final item in VehicleChecklistConfig.items) item.id: items[item.id] == true};

    try {
      await _firestore.runTransaction((transaction) async {
        final existing = await transaction.get(docRef);
        if (existing.exists) throw StateError('already-exists');
        transaction.set(docRef, {
          'driverId': driver.id,
          'driverName': driver.name,
          'vehicleId': vehicle.id,
          'vehicleName': vehicle.name,
          'vehiclePlate': vehicle.plate,
          'vehicleModel': vehicle.model,
          'checklistDate': checklistDateKey(),
          'items': itemMap,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
          'signatureBase64': signatureBase64.trim(),
          'completedAt': FieldValue.serverTimestamp(),
        });
      });
      return null;
    } on StateError catch (error) {
      if (error.message == 'already-exists') {
        return 'Checklist deste veiculo ja foi feito hoje.';
      }
      rethrow;
    } on FirebaseException catch (error) {
      if (error.code == 'already-exists') {
        return 'Checklist deste veiculo ja foi feito hoje.';
      }
      return error.message ?? 'Erro ao salvar checklist.';
    } catch (error) {
      return 'Erro ao salvar checklist: $error';
    }
  }

  @override
  Stream<List<VehicleChecklist>> watchVehicleChecklists(AppUser user) {
    return _auth.authStateChanges().asyncExpand((authUser) {
      if (authUser == null) return Stream.value(const <VehicleChecklist>[]);

      final query = user.role == UserRole.admin
          ? _firestore.collection(FirestorePaths.vehicleChecklists).orderBy('completedAt', descending: true)
          : _firestore
              .collection(FirestorePaths.vehicleChecklists)
              .where('driverId', isEqualTo: user.id)
              .orderBy('completedAt', descending: true);

      return query.snapshots().map((snapshot) => snapshot.docs.map(_checklistFromDoc).toList());
    });
  }

  @override
  Future<String?> startVehicle(String vehicleId, AppUser user) async {
    final authUser = _auth.currentUser;
    if (authUser == null) return 'Sessao expirada. Faca login novamente.';
    if (authUser.uid != user.id) return 'Sessao invalida. Faca login novamente.';
    final driverId = authUser.uid;

    final activeVehicles = await _firestore
        .collection(FirestorePaths.vehicles)
        .where('currentDriverId', isEqualTo: driverId)
        .get();
    for (final doc in activeVehicles.docs) {
      final active = _vehicleFromDoc(doc);
      if (active.status == VehicleStatus.moving && active.id != vehicleId) {
        return 'Voce ja esta usando o veiculo ${active.name}. Pare ele antes de iniciar outro.';
      }
    }

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
  Future<String?> stopVehicle(String vehicleId, AppUser user, String location, {double? distanceKm}) async {
    final authUser = _auth.currentUser;
    if (authUser == null) return 'Sessao expirada. Faca login novamente.';
    if (authUser.uid != user.id) return 'Sessao invalida. Faca login novamente.';
    final driverId = authUser.uid;

    try {
      await _firestore.runTransaction((transaction) async {
        final vehicleRef = _firestore.collection(FirestorePaths.vehicles).doc(vehicleId);
        final vehicleSnap = await transaction.get(vehicleRef);
        if (!vehicleSnap.exists) throw StateError('Veiculo nao encontrado.');
        final current = _vehicleFromDoc(vehicleSnap);
        if (current.status == VehicleStatus.stopped) throw StateError('Este veiculo ja esta parado.');
        if (current.currentDriverId != driverId) {
          throw StateError('Somente o motorista responsavel pode parar o veiculo.');
        }
        final now = Timestamp.now();
        transaction.update(vehicleRef, {
          'status': VehicleStatus.stopped.name,
          'stoppedAt': now,
          'stoppedLocation': location.trim(),
          'currentDriverId': FieldValue.delete(),
          'currentDriverName': FieldValue.delete(),
          'startedAt': FieldValue.delete(),
        });
        final movementRef = _firestore.collection(FirestorePaths.movements).doc();
        transaction.set(movementRef, {
          'vehicleId': vehicleId,
          'vehicleName': current.name,
          'driverId': driverId,
          'driverName': user.name,
          'action': MovementAction.off.name,
          'createdAt': now,
          'location': location.trim(),
          if (distanceKm != null && distanceKm > 0) 'distanceKm': double.parse(distanceKm.toStringAsFixed(2)),
        });
      });
      unawaited(_deleteTrackingDoc(driverId));
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
  Future<void> purgeOrphanedTracking(List<String> driverIds) async {
    if (driverIds.isEmpty) return;

    final uniqueIds = driverIds.toSet();
    final batch = _firestore.batch();
    for (final driverId in uniqueIds) {
      batch.delete(_firestore.collection(FirestorePaths.tracking).doc(driverId));
    }

    try {
      await batch.commit();
    } on FirebaseException catch (error) {
      debugPrint('Falha ao limpar rastros GPS orfaos: ${error.message}');
    }
  }

  Future<void> _deleteTrackingDoc(String driverId) async {
    try {
      await _firestore.collection(FirestorePaths.tracking).doc(driverId).delete();
    } catch (error) {
      debugPrint('GPS: falha ao remover tracking do motorista $driverId: $error');
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
      if (vehicle.hasMaintenancePlan) {
        await _deleteMaintenancePlanFile(vehicleId);
      }
      await doc.reference.delete();
      return null;
    } on FirebaseException catch (error) {
      return error.message;
    }
  }

  @override
  Future<String?> uploadMaintenancePlan(
    AppUser actor,
    String vehicleId,
    List<int> bytes,
    String fileName,
  ) async {
    if (actor.role != UserRole.admin) return 'Somente administradores podem anexar planos.';
    if (bytes.isEmpty) return 'Arquivo vazio.';

    final normalizedName = fileName.trim().isEmpty ? 'plano_manutencao.pdf' : fileName.trim();
    try {
      final storageRef = FirebaseStorage.instance.ref('vehicles/$vehicleId/maintenance/plan.pdf');
      await storageRef.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(contentType: 'application/pdf'),
      );
      final url = await storageRef.getDownloadURL();
      await _firestore.collection(FirestorePaths.vehicles).doc(vehicleId).update({
        'maintenancePlanUrl': url,
        'maintenancePlanFileName': normalizedName,
        'maintenancePlanUpdatedAt': Timestamp.now(),
      });
      return null;
    } on FirebaseException catch (error) {
      return error.message ?? 'Erro ao anexar plano de manutencao.';
    } catch (error) {
      return 'Erro ao anexar plano de manutencao: $error';
    }
  }

  @override
  Future<String?> removeMaintenancePlan(AppUser actor, String vehicleId) async {
    if (actor.role != UserRole.admin) return 'Somente administradores podem remover planos.';
    try {
      await _deleteMaintenancePlanFile(vehicleId);
      await _firestore.collection(FirestorePaths.vehicles).doc(vehicleId).update({
        'maintenancePlanUrl': FieldValue.delete(),
        'maintenancePlanFileName': FieldValue.delete(),
        'maintenancePlanUpdatedAt': FieldValue.delete(),
      });
      return null;
    } on FirebaseException catch (error) {
      return error.message ?? 'Erro ao remover plano de manutencao.';
    }
  }

  Future<void> _deleteMaintenancePlanFile(String vehicleId) async {
    try {
      await FirebaseStorage.instance.ref('vehicles/$vehicleId/maintenance/plan.pdf').delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') {
        debugPrint('Falha ao remover arquivo de manutencao: ${error.message}');
      }
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
  Future<String?> editDriver(AppUser actor, {required String driverId, required String name, required String email, String? password}) async {
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
    if (_auth.currentUser != null) return;

    final secondaryApp = await _createSecondaryApp();
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final secondaryFirestore = FirebaseFirestore.instanceFor(app: secondaryApp);

      var adminReady = false;
      try {
        await secondaryAuth.signInWithEmailAndPassword(email: 'admin@empresa.com', password: '123456');
        adminReady = true;
      } on FirebaseAuthException {
        for (final seed in _seedUsers) {
          await _ensureAuthUserWithSecondary(secondaryAuth, secondaryFirestore, seed);
        }
        await secondaryAuth.signInWithEmailAndPassword(email: 'admin@empresa.com', password: '123456');
        adminReady = true;
      }

      if (!adminReady) return;

      for (final seed in _seedUsers) {
        await _ensureAuthUserWithSecondary(secondaryAuth, secondaryFirestore, seed);
      }

      await secondaryAuth.signInWithEmailAndPassword(email: 'admin@empresa.com', password: '123456');

      final marker = await secondaryFirestore.collection(FirestorePaths.vehicles).doc('vehicle-1').get();
      if (!marker.exists) {
        final batch = secondaryFirestore.batch();
        for (final vehicle in _seedVehicles) {
          batch.set(secondaryFirestore.collection(FirestorePaths.vehicles).doc(vehicle.id), _vehicleToMap(vehicle));
        }
        await batch.commit();
      }
    } catch (error, stackTrace) {
      debugPrint('Seed Firebase: $error\n$stackTrace');
    } finally {
      await secondaryApp.delete();
    }
  }

  Future<void> _ensureAuthUserWithSecondary(
    FirebaseAuth secondaryAuth,
    FirebaseFirestore secondaryFirestore,
    SeedUser seed,
  ) async {
    String uid;
    try {
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: seed.email,
        password: seed.password,
      );
      uid = credential.user!.uid;
      await secondaryFirestore.collection(FirestorePaths.users).doc(uid).set({
        'name': seed.name,
        'email': seed.email,
        'role': seed.role.name,
      });
      return;
    } on FirebaseAuthException catch (error) {
      if (error.code != 'email-already-in-use') rethrow;
      final credential = await secondaryAuth.signInWithEmailAndPassword(
        email: seed.email,
        password: seed.password,
      );
      uid = credential.user!.uid;
    }

    final ref = secondaryFirestore.collection(FirestorePaths.users).doc(uid);
    if ((await ref.get()).exists) return;

    await secondaryAuth.signInWithEmailAndPassword(email: 'admin@empresa.com', password: '123456');
    await ref.set({
      'name': seed.name,
      'email': seed.email,
      'role': seed.role.name,
    });
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

  Future<FirebaseApp> _createSecondaryApp() {
    return Firebase.initializeApp(
      name: 'SecondaryAuth_${DateTime.now().microsecondsSinceEpoch}',
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  Future<AppUser?> _loadAppUser(String uid) async {
    try {
      final cached = await _firestore
          .collection(FirestorePaths.users)
          .doc(uid)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 2));
      if (cached.exists) {
        return _userFromDoc(cached);
      }
    } catch (error) {
      debugPrint('loadAppUser cache: $error');
    }

    try {
      final remote = await _firestore
          .collection(FirestorePaths.users)
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      if (!remote.exists) return null;
      return _userFromDoc(remote);
    } catch (error) {
      debugPrint('loadAppUser remoto: $error');
      if (_cachedUser?.id == uid) return _cachedUser;
      return null;
    }
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
      maintenancePlanUrl: data['maintenancePlanUrl'] as String?,
      maintenancePlanFileName: data['maintenancePlanFileName'] as String?,
      maintenancePlanUpdatedAt: (data['maintenancePlanUpdatedAt'] as Timestamp?)?.toDate(),
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
      distanceKm: (data['distanceKm'] as num?)?.toDouble(),
    );
  }

  DriverTrack _trackFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return DriverTrack(
      driverId: data['driverId'] as String,
      driverName: data['driverName'] as String,
      vehicleId: data['vehicleId'] as String,
      vehicleName: data['vehicleName'] as String,
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      speedKmh: (data['speedKmh'] as num).toDouble(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
      accuracy: (data['accuracy'] as num?)?.toDouble(),
      heading: (data['heading'] as num?)?.toDouble(),
    );
  }

  FleetAnnouncement _announcementFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final responseRaw = data['responseStatus'] as String?;
    return FleetAnnouncement(
      id: doc.id,
      message: data['message'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdByName: data['createdByName'] as String? ?? 'Administrador',
      createdById: data['createdById'] as String?,
      active: data['active'] as bool? ?? true,
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
      targetDriverId: data['targetDriverId'] as String?,
      targetDriverName: data['targetDriverName'] as String?,
      responseStatus: responseRaw == null
          ? null
          : AnnouncementResponseStatus.values.asNameMap()[responseRaw],
      respondedAt: (data['respondedAt'] as Timestamp?)?.toDate(),
      respondedByName: data['respondedByName'] as String?,
      rejectionReason: data['rejectionReason'] as String?,
    );
  }

  FleetAdminAlert _adminAlertFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return FleetAdminAlert(
      id: doc.id,
      announcementId: data['announcementId'] as String? ?? '',
      driverId: data['driverId'] as String? ?? '',
      driverName: data['driverName'] as String? ?? 'Motorista',
      message: data['message'] as String? ?? '',
      responseStatus: AnnouncementResponseStatus.values.byName(data['responseStatus'] as String),
      rejectionReason: data['rejectionReason'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      viewed: data['viewed'] as bool? ?? false,
      viewedAt: (data['viewedAt'] as Timestamp?)?.toDate(),
      isGroupTask: data['isGroupTask'] as bool? ?? false,
    );
  }

  VehicleChecklist _checklistFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    final rawItems = data['items'] as Map<String, dynamic>? ?? {};
    return VehicleChecklist(
      id: doc.id,
      driverId: data['driverId'] as String? ?? '',
      driverName: data['driverName'] as String? ?? 'Motorista',
      vehicleId: data['vehicleId'] as String? ?? '',
      vehicleName: data['vehicleName'] as String? ?? '',
      vehiclePlate: data['vehiclePlate'] as String? ?? '',
      vehicleModel: data['vehicleModel'] as String? ?? '',
      checklistDate: data['checklistDate'] as String? ?? checklistDateKey(),
      items: rawItems.map((key, value) => MapEntry(key, value == true)),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notes: data['notes'] as String?,
      photoUrls: (data['photoUrls'] as List<dynamic>? ?? const []).map((item) => item.toString()).toList(),
      signatureBase64: data['signatureBase64'] as String?,
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
        if (vehicle.maintenancePlanUrl != null) 'maintenancePlanUrl': vehicle.maintenancePlanUrl,
        if (vehicle.maintenancePlanFileName != null) 'maintenancePlanFileName': vehicle.maintenancePlanFileName,
        if (vehicle.maintenancePlanUpdatedAt != null)
          'maintenancePlanUpdatedAt': Timestamp.fromDate(vehicle.maintenancePlanUpdatedAt!),
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
