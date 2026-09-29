import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/iterable_extensions.dart';
import '../../firebase_options.dart';
import '../firebase/firebase_auth_helpers.dart';
import '../firebase/firestore_paths.dart';
import '../models/app_models.dart';
import '../tenant/tenant_ids.dart';
import 'vehicle_maintenance_plan_codec.dart';
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

  String get _sessionCompanyId => _cachedUser?.companyId ?? TenantIds.defaultCompany;

  String _companyIdFromData(Map<String, dynamic>? data) =>
      (data?['companyId'] as String?) ?? TenantIds.defaultCompany;

  String? _ensureDocumentInActorCompany(AppUser actor, Map<String, dynamic>? data, String label) {
    if (_companyIdFromData(data) != actor.companyId) {
      return '$label nao pertence a sua empresa.';
    }
    return null;
  }

  Future<String?> _ensureAdminManagesUser(AppUser actor, String userId) async {
    if (actor.role != UserRole.admin) return 'Somente administradores podem alterar cadastros.';
    final doc = await _firestore.collection(FirestorePaths.users).doc(userId).get();
    if (!doc.exists) return 'Usuario nao encontrado.';
    return _ensureDocumentInActorCompany(actor, doc.data(), 'Usuario');
  }

  Future<String?> _validateTargetDriver(AppUser actor, String? targetDriverId) async {
    if (targetDriverId == null || targetDriverId.trim().isEmpty) return null;
    final doc = await _firestore.collection(FirestorePaths.users).doc(targetDriverId).get();
    if (!doc.exists) return 'Motorista selecionado nao encontrado.';
    final data = doc.data()!;
    final companyError = _ensureDocumentInActorCompany(actor, data, 'Motorista');
    if (companyError != null) return companyError;
    if (data['role'] != UserRole.driver.name) return 'Selecione um motorista valido.';
    return null;
  }

  Future<String?> _ensureVehicleInUserCompany(AppUser user, String vehicleId) async {
    final doc = await _firestore.collection(FirestorePaths.vehicles).doc(vehicleId).get();
    if (!doc.exists) return 'Veiculo nao encontrado.';
    if (_companyIdFromData(doc.data()) != user.companyId) {
      return 'Este veiculo nao pertence a sua empresa.';
    }
    return null;
  }

  @override
  AppUser? get currentUser => _cachedUser;

  @override
  bool get hasPersistedAuthSession => _auth.currentUser != null;

  @override
  Future<AppUser?> refreshCurrentUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) {
      _cachedUser = null;
      return null;
    }

    try {
      final remote = await _firestore
          .collection(FirestorePaths.users)
          .doc(firebaseUser.uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      if (!remote.exists) return _cachedUser;
      _cachedUser = _userFromDoc(remote);
      return _cachedUser;
    } catch (error) {
      debugPrint('refreshCurrentUser: $error');
      return _cachedUser;
    }
  }

  @override
  Future<AppUser?> restoreSessionIfNeeded() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) {
      _cachedUser = null;
      return null;
    }
    if (_cachedUser?.id == firebaseUser.uid) return _cachedUser;

    final email = firebaseUser.email?.trim().toLowerCase() ?? '';
    final loaded = await _loadAppUser(firebaseUser.uid) ?? await _recoverAdminProfile(firebaseUser.uid, email);
    if (loaded != null) {
      _cachedUser = loaded;
      return loaded;
    }
    return _cachedUser;
  }

  Stream<List<T>> _liveQuery<T>(Stream<List<T>> Function() build) {
    if (_auth.currentUser == null) return Stream.value(const []);
    return build();
  }

  bool get _isAdminSession => _cachedUser?.role == UserRole.admin;

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
        continue;
      }

      final loaded = await _loadAppUser(firebaseUser.uid);
      if (loaded != null) {
        _cachedUser = loaded;
        yield loaded;
      } else {
        yield _cachedUser;
      }
    }
  }

  @override
  Future<String?> login(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final uid = credential.user!.uid;
      _cachedUser = await _loadAppUser(uid) ?? await _recoverAdminProfile(uid, normalizedEmail);
      if (_cachedUser == null) {
        return 'Perfil incompleto no Firestore. Publique as regras (firebase deploy --only firestore:rules) '
            'e tente de novo, ou apague este e-mail em Authentication e use "Criar empresa" novamente.';
      }
      await _ensureUserProfileHasCompanyId(_cachedUser!);
      return null;
    } on FirebaseAuthException catch (error) {
      return _authErrorMessage(error);
    }
  }

  @override
  Future<String?> registerCompany({
    required String companyName,
    required String adminName,
    required String email,
    required String password,
  }) async {
    final trimmedCompany = companyName.trim();
    final trimmedName = adminName.trim();
    final normalizedEmail = email.trim().toLowerCase();
    if (trimmedCompany.length < 2) return 'Informe o nome da empresa.';
    if (trimmedName.length < 2) return 'Informe seu nome.';
    if (password.length < 6) return 'Senha com minimo 6 caracteres.';

    final companyId = _generateCompanyId(trimmedCompany);

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final uid = credential.user!.uid;

      final companyRef = _firestore.collection(FirestorePaths.companies).doc(companyId);
      final userRef = _firestore.collection(FirestorePaths.users).doc(uid);

      await companyRef.set({
        'name': trimmedCompany,
        'active': true,
        'ownerId': uid,
        'plan': 'trial',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await userRef.set({
        'name': trimmedName,
        'email': normalizedEmail,
        'role': UserRole.admin.name,
        'companyId': companyId,
      });

      _cachedUser = AppUser(
        id: uid,
        name: trimmedName,
        email: normalizedEmail,
        password: '',
        role: UserRole.admin,
        companyId: companyId,
      );
      return null;
    } on FirebaseAuthException catch (error) {
      return _authErrorMessage(error);
    } on FirebaseException catch (error) {
      debugPrint('registerCompany Firestore: $error');
      final recovered = await _recoverAdminProfile(_auth.currentUser!.uid, normalizedEmail);
      if (recovered != null) {
        _cachedUser = recovered;
        return null;
      }
      return '${error.message ?? 'Erro ao salvar empresa.'} '
          'Execute: firebase deploy --only firestore:rules --project device-streaming-53bb0fb6';
    }
  }

  Future<AppUser?> _recoverAdminProfile(String uid, String normalizedEmail) async {
    try {
      final companies = await _firestore
          .collection(FirestorePaths.companies)
          .where('ownerId', isEqualTo: uid)
          .limit(1)
          .get();
      if (companies.docs.isEmpty) return null;

      final companyId = companies.docs.first.id;
      final existingUser = await _firestore.collection(FirestorePaths.users).doc(uid).get();
      if (existingUser.exists) {
        return _userFromDoc(existingUser);
      }

      final fallbackName = normalizedEmail.split('@').first;
      await _firestore.collection(FirestorePaths.users).doc(uid).set({
        'name': fallbackName,
        'email': normalizedEmail,
        'role': UserRole.admin.name,
        'companyId': companyId,
      });
      return AppUser(
        id: uid,
        name: fallbackName,
        email: normalizedEmail,
        password: '',
        role: UserRole.admin,
        companyId: companyId,
      );
    } catch (error) {
      debugPrint('_recoverAdminProfile: $error');
      return null;
    }
  }

  String _generateCompanyId(String companyName) {
    final base = companyName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final slug = base.isEmpty ? 'empresa' : (base.length > 24 ? base.substring(0, 24) : base);
    return 'co-$slug-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
  }

  @override
  Future<String?> sendPasswordResetEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return 'Informe o e-mail da sua conta.';

    try {
      await sendPasswordResetEmailToAccount(_auth, normalized);
      return null;
    } on FirebaseAuthException catch (error) {
      return passwordResetErrorMessage(error);
    }
  }

  @override
  Future<void> logout() async {
    await _auth.signOut();
    _cachedUser = null;
  }

  @override
  Stream<List<Vehicle>> watchVehicles() {
    return _liveQuery(
      () => _firestore
          .collection(FirestorePaths.vehicles)
          .where('companyId', isEqualTo: _sessionCompanyId)
          .orderBy('name')
          .snapshots()
          .asyncMap(_mergeLegacyVehiclesIntoList),
    );
  }

  @override
  Future<List<Vehicle>> fetchVehicles() async {
    if (_auth.currentUser == null) return const [];
    final snapshot = await _firestore
        .collection(FirestorePaths.vehicles)
        .where('companyId', isEqualTo: _sessionCompanyId)
        .orderBy('name')
        .get();
    return _mergeLegacyVehiclesIntoList(snapshot);
  }

  Future<List<Vehicle>> _mergeLegacyVehiclesIntoList(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final byId = {for (final doc in snapshot.docs) doc.id: _vehicleFromDoc(doc)};
    if (_shouldIncludeLegacyTenantDocs()) {
      for (final doc in await _loadLegacyDocs(FirestorePaths.vehicles)) {
        byId.putIfAbsent(doc.id, () => _vehicleFromDoc(doc));
      }
    }
    final list = byId.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  Stream<List<Movement>> watchMovements() {
    return _liveQuery(() {
      final uid = _auth.currentUser!.uid;
      final query = _isAdminSession
          ? _firestore
              .collection(FirestorePaths.movements)
              .where('companyId', isEqualTo: _sessionCompanyId)
              .orderBy('createdAt', descending: true)
          : _firestore.collection(FirestorePaths.movements).where('driverId', isEqualTo: uid).orderBy('createdAt', descending: true);
      return query.snapshots().map((snapshot) => snapshot.docs.map(_movementFromDoc).toList());
    });
  }

  @override
  Stream<List<AppUser>> watchUsers() {
    return _liveQuery(() {
      final uid = _auth.currentUser!.uid;
      if (_isAdminSession) {
        return _firestore
            .collection(FirestorePaths.users)
            .where('companyId', isEqualTo: _sessionCompanyId)
            .orderBy('name')
            .snapshots()
            .asyncMap(_mergeLegacyUsersIntoList);
      }
      return _firestore.collection(FirestorePaths.users).doc(uid).snapshots().map(
            (snapshot) => snapshot.exists ? [_userFromDoc(snapshot)] : const <AppUser>[],
          );
    });
  }

  @override
  Stream<List<DriverTrack>> watchDriverTracks() {
    return _liveQuery(() {
      final uid = _auth.currentUser!.uid;
      if (_isAdminSession) {
        return _firestore
            .collection(FirestorePaths.tracking)
            .where('companyId', isEqualTo: _sessionCompanyId)
            .snapshots()
            .map(
              (snapshot) => snapshot.docs.map(_trackFromDoc).toList(),
            );
      }
      return _firestore.collection(FirestorePaths.tracking).doc(uid).snapshots().map(
            (snapshot) => snapshot.exists ? [_trackFromDoc(snapshot)] : const <DriverTrack>[],
          );
    });
  }

  @override
  Stream<List<FleetAnnouncement>> watchAnnouncementsForUser(AppUser user) {
    if (_auth.currentUser == null) return Stream.value(const <FleetAnnouncement>[]);

    return _firestore
        .collection(FirestorePaths.announcements)
        .where('companyId', isEqualTo: user.companyId)
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
    String? destinationAddress,
    double? destinationLatitude,
    double? destinationLongitude,
  }) async {
    if (actor.role != UserRole.admin) return 'Somente administradores podem publicar tarefas.';
    final text = message.trim();
    if (text.isEmpty) return 'Escreva a tarefa antes de publicar.';
    if (expiresAt != null && !expiresAt.isAfter(DateTime.now())) {
      return 'A data de validade precisa ser futura.';
    }

    final driverError = await _validateTargetDriver(actor, targetDriverId);
    if (driverError != null) return driverError;

    try {
      await _firestore.collection(FirestorePaths.announcements).add({
        'message': text,
        'createdAt': FieldValue.serverTimestamp(),
        'createdById': actor.id,
        'createdByName': actor.name,
        'companyId': actor.companyId,
        'active': true,
        if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
        if (targetDriverId != null) 'targetDriverId': targetDriverId,
        if (targetDriverName != null) 'targetDriverName': targetDriverName,
        if (destinationAddress != null) 'destinationAddress': destinationAddress,
        if (destinationLatitude != null) 'destinationLatitude': destinationLatitude,
        if (destinationLongitude != null) 'destinationLongitude': destinationLongitude,
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
      final doc = await _firestore.collection(FirestorePaths.announcements).doc(announcementId).get();
      if (!doc.exists) return null;
      final companyError = _ensureDocumentInActorCompany(actor, doc.data(), 'Tarefa');
      if (companyError != null) return companyError;

      await _firestore.collection(FirestorePaths.announcements).doc(announcementId).delete();
      return null;
    } on FirebaseException catch (error) {
      return error.message ?? 'Erro ao remover tarefa.';
    }
  }

  @override
  Future<String?> startAnnouncement(
    AppUser driver,
    String announcementId, {
    List<({double lat, double lng})>? routePoints,
  }) async {
    if (driver.role != UserRole.driver) return 'Somente motoristas podem iniciar tarefas.';

    try {
      final authUid = _auth.currentUser?.uid;
      if (authUid == null) return 'Sessao expirada. Faca login novamente.';
      if (authUid != driver.id) return 'Sessao invalida. Faca login novamente.';

      final docRef = _firestore.collection(FirestorePaths.announcements).doc(announcementId);
      final doc = await docRef.get(const GetOptions(source: Source.server));
      if (!doc.exists) throw StateError('Tarefa nao encontrada.');

      final announcement = _announcementFromDoc(doc);
      if (_companyIdFromData(doc.data()) != driver.companyId) {
        throw StateError('Esta tarefa nao pertence a sua empresa.');
      }
      if (announcement.isExpired) throw StateError('Esta tarefa expirou.');
      if (!announcement.isAvailableToStart) {
        if (announcement.isInProgress) {
          throw StateError(
            'Esta tarefa ja foi iniciada por ${announcement.startedByName ?? 'outro motorista'}.',
          );
        }
        throw StateError('Esta tarefa nao esta mais disponivel.');
      }
      if (!announcement.isGroupTask && announcement.targetDriverId != driver.id) {
        throw StateError('Esta tarefa nao foi destinada a voce.');
      }

      await docRef.update({
        'startedById': authUid,
        'startedByName': driver.name,
        'startedAt': FieldValue.serverTimestamp(),
        if (routePoints != null && routePoints.isNotEmpty)
          'routePoints': [
            for (final point in routePoints) {'lat': point.lat, 'lng': point.lng},
          ],
      });
      return null;
    } on StateError catch (error) {
      return error.message;
    } on FirebaseException catch (error) {
      debugPrint('startAnnouncement firebase: code=${error.code} message=${error.message}');
      if (error.code == 'permission-denied') {
        return 'Nao foi possivel iniciar a tarefa. Peça ao admin para remover e publicar de novo, ou tente outro motorista.';
      }
      return error.message ?? 'Erro ao iniciar tarefa.';
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
        if (_companyIdFromData(doc.data()) != driver.companyId) {
          throw StateError('Esta tarefa nao pertence a sua empresa.');
        }
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

        if (status == AnnouncementResponseStatus.rejected) {
          if (announcement.isInProgress) {
            throw StateError('Nao e possivel recusar uma tarefa ja iniciada.');
          }
        } else {
          if (!announcement.isInProgress) {
            throw StateError('Inicie a tarefa antes de concluir.');
          }
          if (announcement.startedById != authUid) {
            throw StateError(
              'Esta tarefa esta em andamento por ${announcement.startedByName ?? 'outro motorista'}.',
            );
          }
        }

        final alertRef = _firestore.collection(FirestorePaths.adminAlerts).doc();
        transaction.set(alertRef, {
          'announcementId': announcementId,
          'driverId': authUid,
          'driverName': driver.name,
          'message': announcement.message,
          'companyId': driver.companyId,
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
    return _liveQuery(
      () => _firestore
          .collection(FirestorePaths.adminAlerts)
          .where('companyId', isEqualTo: _sessionCompanyId)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs.map(_adminAlertFromDoc).toList()),
    );
  }

  @override
  Future<void> markAdminAlertsViewed(AppUser admin) async {
    if (admin.role != UserRole.admin) return;

    final unread = await _firestore
        .collection(FirestorePaths.adminAlerts)
        .where('companyId', isEqualTo: admin.companyId)
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
  Future<String?> submitDriverIssueReport(
    AppUser driver, {
    required String message,
    String? vehicleId,
    String? vehicleName,
  }) async {
    if (driver.role != UserRole.driver) return 'Somente motoristas podem enviar relatos.';
    final trimmed = message.trim();
    if (trimmed.isEmpty) return 'Descreva o problema antes de enviar.';

    try {
      await _firestore.collection(FirestorePaths.driverReports).add({
        'driverId': driver.id,
        'driverName': driver.name,
        'companyId': driver.companyId,
        'message': trimmed,
        if (vehicleId != null) 'vehicleId': vehicleId,
        if (vehicleName != null) 'vehicleName': vehicleName,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return null;
    } on FirebaseException catch (error) {
      return error.message ?? 'Erro ao enviar relato.';
    }
  }

  @override
  Stream<List<DriverIssueReport>> watchDriverIssueReports(AppUser user) {
    if (_auth.currentUser == null) return Stream.value(const <DriverIssueReport>[]);

    final query = user.role == UserRole.admin
        ? _firestore.collection(FirestorePaths.driverReports).where('companyId', isEqualTo: user.companyId)
        : _firestore.collection(FirestorePaths.driverReports).where('driverId', isEqualTo: user.id);

    return query.snapshots().map((snapshot) {
      final reports = snapshot.docs.map(_driverIssueReportFromDoc).toList();
      reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return reports;
    });
  }

  @override
  Future<String?> replyToDriverIssueReport(AppUser admin, String reportId, String reply) async {
    if (admin.role != UserRole.admin) return 'Somente administradores podem responder relatos.';
    final trimmed = reply.trim();
    if (trimmed.isEmpty) return 'Escreva uma resposta antes de enviar.';

    try {
      await _firestore.collection(FirestorePaths.driverReports).doc(reportId).update({
        'adminReply': trimmed,
        'repliedAt': FieldValue.serverTimestamp(),
        'repliedByName': admin.name,
      });
      return null;
    } on FirebaseException catch (error) {
      return error.message ?? 'Erro ao enviar resposta.';
    }
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

    final vehicleCompanyError = await _ensureVehicleInUserCompany(driver, vehicle.id);
    if (vehicleCompanyError != null) return vehicleCompanyError;

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
          'companyId': driver.companyId,
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
    if (_auth.currentUser == null) return Stream.value(const <VehicleChecklist>[]);

    final query = user.role == UserRole.admin
        ? _firestore.collection(FirestorePaths.vehicleChecklists).where('companyId', isEqualTo: user.companyId)
        : _firestore.collection(FirestorePaths.vehicleChecklists).where('driverId', isEqualTo: user.id);

    return query.snapshots().map((snapshot) {
      final checklists = snapshot.docs.map(_checklistFromDoc).toList()
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
      return checklists;
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
        .where('companyId', isEqualTo: user.companyId)
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
        if (_companyIdFromData(vehicleSnap.data()) != user.companyId) {
          throw StateError('Este veiculo nao pertence a sua empresa.');
        }
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
          'stoppedLatitude': FieldValue.delete(),
          'stoppedLongitude': FieldValue.delete(),
        });
        final movementRef = _firestore.collection(FirestorePaths.movements).doc();
        transaction.set(movementRef, {
          'vehicleId': vehicleId,
          'vehicleName': current.name,
          'driverId': driverId,
          'driverName': user.name,
          'companyId': user.companyId,
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
  Future<String?> stopVehicle(
    String vehicleId,
    AppUser user,
    String location, {
    double? distanceKm,
    double? stoppedLatitude,
    double? stoppedLongitude,
  }) async {
    final authUser = _auth.currentUser;
    if (authUser == null) return 'Sessao expirada. Faca login novamente.';
    if (authUser.uid != user.id) return 'Sessao invalida. Faca login novamente.';
    final driverId = authUser.uid;

    var latitude = stoppedLatitude;
    var longitude = stoppedLongitude;
    if (latitude == null || longitude == null) {
      try {
        final trackingDoc = await _firestore.collection(FirestorePaths.tracking).doc(driverId).get();
        if (trackingDoc.exists) {
          final data = trackingDoc.data();
          latitude ??= (data?['latitude'] as num?)?.toDouble();
          longitude ??= (data?['longitude'] as num?)?.toDouble();
        }
      } catch (error) {
        debugPrint('GPS: falha ao ler ultima posicao do tracking: $error');
      }
    }

    try {
      await _firestore.runTransaction((transaction) async {
        final vehicleRef = _firestore.collection(FirestorePaths.vehicles).doc(vehicleId);
        final vehicleSnap = await transaction.get(vehicleRef);
        if (!vehicleSnap.exists) throw StateError('Veiculo nao encontrado.');
        final current = _vehicleFromDoc(vehicleSnap);
        if (_companyIdFromData(vehicleSnap.data()) != user.companyId) {
          throw StateError('Este veiculo nao pertence a sua empresa.');
        }
        if (current.status == VehicleStatus.stopped) throw StateError('Este veiculo ja esta parado.');
        if (current.currentDriverId != driverId) {
          throw StateError('Somente o motorista responsavel pode parar o veiculo.');
        }
        final now = Timestamp.now();
        final updateData = <String, dynamic>{
          'status': VehicleStatus.stopped.name,
          'stoppedAt': now,
          'stoppedLocation': location.trim(),
          'currentDriverId': FieldValue.delete(),
          'currentDriverName': FieldValue.delete(),
          'startedAt': FieldValue.delete(),
        };
        if (distanceKm != null && distanceKm > 0 && current.odometerKm != null) {
          updateData['odometerKm'] = double.parse((current.odometerKm! + distanceKm).toStringAsFixed(1));
        }
        if (latitude != null && longitude != null) {
          updateData['stoppedLatitude'] = latitude;
          updateData['stoppedLongitude'] = longitude;
        }
        transaction.update(vehicleRef, updateData);
        final movementRef = _firestore.collection(FirestorePaths.movements).doc();
        transaction.set(movementRef, {
          'vehicleId': vehicleId,
          'vehicleName': current.name,
          'driverId': driverId,
          'driverName': user.name,
          'companyId': user.companyId,
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
        'companyId': actor.companyId,
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
    final trimmedName = name.trim();
    try {
      await _firestore.collection(FirestorePaths.vehicles).doc(vehicleId).update({
        'name': trimmedName,
        'model': model.trim(),
        'plate': plate.trim().toUpperCase(),
      });
      unawaited(_propagateVehicleNameChange(vehicleId: vehicleId, name: trimmedName));
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
      await _deleteMaintenanceChunks(vehicleId);
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
    if (bytes.length > VehicleMaintenancePlanLimits.maxFileSizeBytes) {
      return 'Arquivo muito grande. Maximo ${VehicleMaintenancePlanLimits.maxFileSizeBytes ~/ (1024 * 1024)} MB.';
    }

    final normalizedName = fileName.trim().isEmpty ? 'plano_manutencao.pdf' : fileName.trim();
    if (!normalizedName.toLowerCase().endsWith('.pdf')) {
      return 'Envie um arquivo PDF.';
    }

    try {
      final vehicleRef = _firestore.collection(FirestorePaths.vehicles).doc(vehicleId);
      final vehicleSnap = await vehicleRef.get();
      if (!vehicleSnap.exists) return 'Veiculo nao encontrado.';

      await _deleteMaintenanceChunks(vehicleId);

      final chunks = VehicleMaintenancePlanCodec.split(Uint8List.fromList(bytes));
      for (var index = 0; index < chunks.length; index++) {
        await vehicleRef.collection(FirestorePaths.maintenanceChunks).doc(_chunkDocId(index)).set({
          'index': index,
          'data': base64Encode(chunks[index]),
        });
      }

      await vehicleRef.update({
        'maintenancePlanFileName': normalizedName,
        'maintenancePlanUpdatedAt': Timestamp.now(),
        'maintenancePlanSizeBytes': bytes.length,
        'maintenancePlanChunkCount': chunks.length,
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
      await _deleteMaintenanceChunks(vehicleId);
      await _firestore.collection(FirestorePaths.vehicles).doc(vehicleId).update({
        'maintenancePlanFileName': FieldValue.delete(),
        'maintenancePlanUpdatedAt': FieldValue.delete(),
        'maintenancePlanSizeBytes': FieldValue.delete(),
        'maintenancePlanChunkCount': FieldValue.delete(),
      });
      return null;
    } on FirebaseException catch (error) {
      return error.message ?? 'Erro ao remover plano de manutencao.';
    }
  }

  @override
  Future<Uint8List?> fetchMaintenancePlanBytes(String vehicleId) async {
    if (_auth.currentUser == null) return null;

    try {
      final vehicleRef = _firestore.collection(FirestorePaths.vehicles).doc(vehicleId);
      final vehicleSnap = await vehicleRef.get();
      if (!vehicleSnap.exists) return null;

      final vehicle = _vehicleFromDoc(vehicleSnap);
      if (!vehicle.hasMaintenancePlan) return null;

      final snapshot = await vehicleRef.collection(FirestorePaths.maintenanceChunks).get();
      if (snapshot.docs.isEmpty) return null;

      final ordered = snapshot.docs.toList()
        ..sort((a, b) {
          final ai = a.data()['index'] as int? ?? 0;
          final bi = b.data()['index'] as int? ?? 0;
          return ai.compareTo(bi);
        });

      return VehicleMaintenancePlanCodec.merge(
        ordered.map((doc) => doc.data()['data'] as String).toList(),
      );
    } on FirebaseException catch (error) {
      debugPrint('Falha ao baixar plano de manutencao: ${error.message}');
      return null;
    }
  }

  @override
  Future<String?> updateVehicleMaintenance(
    AppUser actor,
    String vehicleId, {
    double? odometerKm,
    double? nextServiceKm,
    DateTime? nextServiceDate,
    DateTime? lastServiceDate,
    String? lastServiceNotes,
  }) async {
    if (actor.role != UserRole.admin) return 'Somente administradores podem alterar manutencao.';
    try {
      final update = <String, dynamic>{};
      if (odometerKm != null) update['odometerKm'] = double.parse(odometerKm.toStringAsFixed(1));
      if (nextServiceKm != null) update['nextServiceKm'] = double.parse(nextServiceKm.toStringAsFixed(1));
      if (nextServiceDate != null) update['nextServiceDate'] = Timestamp.fromDate(nextServiceDate);
      if (lastServiceDate != null) update['lastServiceDate'] = Timestamp.fromDate(lastServiceDate);
      if (lastServiceNotes != null) update['lastServiceNotes'] = lastServiceNotes.trim();
      if (update.isEmpty) return 'Informe ao menos um campo de manutencao.';

      await _firestore.collection(FirestorePaths.vehicles).doc(vehicleId).update(update);
      return null;
    } on FirebaseException catch (error) {
      return error.message ?? 'Erro ao salvar manutencao.';
    }
  }

  @override
  Future<String?> addMaintenanceLog(
    AppUser actor,
    String vehicleId, {
    required DateTime serviceDate,
    required double odometerKm,
    required String serviceType,
    String? notes,
    double? cost,
  }) async {
    if (actor.role != UserRole.admin) return 'Somente administradores podem registrar servicos.';
    final type = serviceType.trim();
    if (type.isEmpty) return 'Informe o tipo de servico.';

    try {
      final vehicleRef = _firestore.collection(FirestorePaths.vehicles).doc(vehicleId);
      final vehicleSnap = await vehicleRef.get();
      if (!vehicleSnap.exists) return 'Veiculo nao encontrado.';

      await vehicleRef.collection(FirestorePaths.maintenanceLogs).add({
        'serviceDate': Timestamp.fromDate(serviceDate),
        'odometerKm': double.parse(odometerKm.toStringAsFixed(1)),
        'serviceType': type,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        if (cost != null && cost > 0) 'cost': double.parse(cost.toStringAsFixed(2)),
        'createdByName': actor.name,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await vehicleRef.update({
        'odometerKm': double.parse(odometerKm.toStringAsFixed(1)),
        'lastServiceDate': Timestamp.fromDate(serviceDate),
        'lastServiceNotes': notes?.trim().isNotEmpty == true ? notes!.trim() : type,
      });
      return null;
    } on FirebaseException catch (error) {
      return error.message ?? 'Erro ao registrar servico.';
    }
  }

  @override
  Stream<List<MaintenanceLog>> watchMaintenanceLogs(String vehicleId) {
    return _firestore
        .collection(FirestorePaths.vehicles)
        .doc(vehicleId)
        .collection(FirestorePaths.maintenanceLogs)
        .snapshots()
        .map((snapshot) {
      final logs = snapshot.docs.map(_maintenanceLogFromDoc).toList();
      logs.sort((a, b) => b.serviceDate.compareTo(a.serviceDate));
      return logs;
    });
  }

  MaintenanceLog _maintenanceLogFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return MaintenanceLog(
      id: doc.id,
      vehicleId: doc.reference.parent.parent?.id ?? '',
      serviceDate: (data['serviceDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      odometerKm: (data['odometerKm'] as num?)?.toDouble() ?? 0,
      serviceType: data['serviceType'] as String? ?? 'Servico',
      notes: data['notes'] as String?,
      cost: (data['cost'] as num?)?.toDouble(),
      createdByName: data['createdByName'] as String? ?? 'Admin',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Future<void> _deleteMaintenanceChunks(String vehicleId) async {
    final chunksRef = _firestore.collection(FirestorePaths.vehicles).doc(vehicleId).collection(FirestorePaths.maintenanceChunks);
    final snapshot = await chunksRef.get();
    if (snapshot.docs.isEmpty) return;

    var batch = _firestore.batch();
    var ops = 0;
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
      ops++;
      if (ops >= 450) {
        await batch.commit();
        batch = _firestore.batch();
        ops = 0;
      }
    }
    if (ops > 0) {
      await batch.commit();
    }
  }

  String _chunkDocId(int index) => index.toString().padLeft(4, '0');

  @override
  Future<String?> addDriver(AppUser actor, {required String name, required String email, required String password}) async {
    if (actor.role != UserRole.admin) return 'Somente administradores podem alterar cadastros.';
    try {
      final credential = await _createAuthUserWithoutSwitchingSession(email: email.trim().toLowerCase(), password: password);
      await _firestore.collection(FirestorePaths.users).doc(credential.user!.uid).set({
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'role': UserRole.driver.name,
        'companyId': actor.companyId,
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
    final accessError = await _ensureAdminManagesUser(actor, driverId);
    if (accessError != null) return accessError;
    final trimmedName = name.trim();
    final normalizedEmail = email.trim().toLowerCase();
    try {
      await _firestore.collection(FirestorePaths.users).doc(driverId).update({
        'name': trimmedName,
        'email': normalizedEmail,
      });
      unawaited(_propagateDriverProfileChange(driverId: driverId, name: trimmedName));

      if (_cachedUser?.id == driverId) {
        _cachedUser = AppUser(
          id: driverId,
          name: trimmedName,
          email: normalizedEmail,
          password: '',
          role: _cachedUser!.role,
          companyId: _cachedUser!.companyId,
        );
      }
      return null;
    } on FirebaseException catch (error) {
      return error.message;
    }
  }

  Future<void> _propagateDriverProfileChange({required String driverId, required String name}) async {
    try {
      final companyId = _cachedUser?.companyId ?? TenantIds.defaultCompany;
      final vehicles = await _firestore
          .collection(FirestorePaths.vehicles)
          .where('companyId', isEqualTo: companyId)
          .where('currentDriverId', isEqualTo: driverId)
          .get();
      for (final doc in vehicles.docs) {
        await doc.reference.update({'currentDriverName': name});
      }

      final trackingRef = _firestore.collection(FirestorePaths.tracking).doc(driverId);
      final trackingSnap = await trackingRef.get();
      if (trackingSnap.exists) {
        await trackingRef.update({'driverName': name});
      }
    } catch (error) {
      debugPrint('Sync nome motorista: $error');
    }
  }

  Future<void> _propagateVehicleNameChange({required String vehicleId, required String name}) async {
    try {
      final companyId = _cachedUser?.companyId ?? TenantIds.defaultCompany;
      final tracks = await _firestore
          .collection(FirestorePaths.tracking)
          .where('companyId', isEqualTo: companyId)
          .where('vehicleId', isEqualTo: vehicleId)
          .get();
      for (final doc in tracks.docs) {
        await doc.reference.update({'vehicleName': name});
      }
    } catch (error) {
      debugPrint('Sync nome veiculo: $error');
    }
  }

  @override
  Future<String?> deleteDriver(AppUser actor, String driverId) async {
    final accessError = await _ensureAdminManagesUser(actor, driverId);
    if (accessError != null) return accessError;
    try {
      final vehicles = await _firestore
          .collection(FirestorePaths.vehicles)
          .where('companyId', isEqualTo: actor.companyId)
          .where('currentDriverId', isEqualTo: driverId)
          .limit(1)
          .get();
      if (vehicles.docs.isNotEmpty) return 'Nao e possivel excluir um motorista que esta usando um veiculo.';
      await _firestore.collection(FirestorePaths.users).doc(driverId).delete();
      return null;
    } on FirebaseException catch (error) {
      return error.message;
    }
  }

  bool _shouldIncludeLegacyTenantDocs() => _sessionCompanyId == TenantIds.defaultCompany;

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadLegacyDocs(String collection) async {
    if (!_shouldIncludeLegacyTenantDocs()) return const [];
    final snapshot = await _firestore.collection(collection).limit(500).get();
    return snapshot.docs.where((doc) => !doc.data().containsKey('companyId')).toList();
  }

  Future<List<AppUser>> _mergeLegacyUsersIntoList(QuerySnapshot<Map<String, dynamic>> snapshot) async {
    final byId = {for (final doc in snapshot.docs) doc.id: _userFromDoc(doc)};
    for (final doc in await _loadLegacyDocs(FirestorePaths.users)) {
      byId.putIfAbsent(doc.id, () => _userFromDoc(doc));
    }
    final list = byId.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<void> _ensureUserProfileHasCompanyId(AppUser user) async {
    try {
      final ref = _firestore.collection(FirestorePaths.users).doc(user.id);
      final doc = await ref.get();
      if (!doc.exists) {
        await ref.set({
          'name': user.name,
          'email': user.email,
          'role': user.role.name,
          'companyId': user.companyId,
        }, SetOptions(merge: true));
        return;
      }
      if (doc.data()?.containsKey('companyId') != true) {
        await ref.set({'companyId': user.companyId}, SetOptions(merge: true));
      }
    } catch (error) {
      debugPrint('ensureUserProfileHasCompanyId: $error');
    }
  }

  @override
  Future<void> repairLegacyTenantDataForSession() async {
    final user = _cachedUser;
    if (user == null || user.role != UserRole.admin) return;
    if (user.companyId != TenantIds.defaultCompany) return;
    try {
      await _backfillMissingCompanyId(_firestore, trackingUsesCurrentSession: true);
      debugPrint('repairLegacyTenantData: concluido para empresa principal.');
    } catch (error, stackTrace) {
      debugPrint('repairLegacyTenantData: $error\n$stackTrace');
    }
  }

  Future<void> _backfillMissingCompanyId(
    FirebaseFirestore firestore, {
    required bool trackingUsesCurrentSession,
  }) async {
    const collections = [
      FirestorePaths.vehicles,
      FirestorePaths.announcements,
      FirestorePaths.movements,
      FirestorePaths.adminAlerts,
      FirestorePaths.driverReports,
      FirestorePaths.vehicleChecklists,
    ];

    for (final collection in collections) {
      await _backfillCompanyIdOnCollection(firestore, collection);
    }

    await _backfillCompanyIdOnCollection(firestore, FirestorePaths.users);
    if (trackingUsesCurrentSession) {
      final tenantId = _cachedUser?.companyId ?? TenantIds.defaultCompany;
      await _backfillCompanyIdOnCollection(
        firestore,
        FirestorePaths.tracking,
        companyIdForDoc: (doc) => _companyIdForTrackingDoc(firestore, doc),
        onlyCompanyId: tenantId,
      );
    }
  }

  Future<String> _companyIdForTrackingDoc(FirebaseFirestore firestore, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final driverId = doc.id;
    try {
      final userDoc = await firestore.collection(FirestorePaths.users).doc(driverId).get();
      if (userDoc.exists) {
        return _companyIdFromData(userDoc.data());
      }
    } catch (_) {}
    return TenantIds.defaultCompany;
  }

  Future<void> _backfillCompanyIdOnCollection(
    FirebaseFirestore firestore,
    String collection, {
    Future<String> Function(QueryDocumentSnapshot<Map<String, dynamic>> doc)? companyIdForDoc,
    String? onlyCompanyId,
  }) async {
    const pageSize = 200;
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    var totalUpdates = 0;

    while (true) {
      Query<Map<String, dynamic>> query = firestore.collection(collection).limit(pageSize);
      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }
      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) break;

      var batch = firestore.batch();
      var batchCount = 0;

      for (final doc in snapshot.docs) {
        if (doc.data().containsKey('companyId')) continue;
        final companyId = companyIdForDoc != null
            ? await companyIdForDoc(doc)
            : TenantIds.defaultCompany;
        if (onlyCompanyId != null && companyId != onlyCompanyId) continue;
        batch.update(doc.reference, {'companyId': companyId});
        batchCount++;
        totalUpdates++;

        if (batchCount >= 400) {
          await batch.commit();
          batch = firestore.batch();
          batchCount = 0;
        }
      }

      if (batchCount > 0) {
        await batch.commit();
      }

      cursor = snapshot.docs.last;
      if (snapshot.docs.length < pageSize) break;
    }

    if (totalUpdates > 0) {
      debugPrint('Backfill companyId: $totalUpdates doc(s) em $collection');
    }
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
      companyId: _companyIdFromData(data),
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
      stoppedLatitude: (data['stoppedLatitude'] as num?)?.toDouble(),
      stoppedLongitude: (data['stoppedLongitude'] as num?)?.toDouble(),
      maintenancePlanFileName: data['maintenancePlanFileName'] as String?,
      maintenancePlanUpdatedAt: (data['maintenancePlanUpdatedAt'] as Timestamp?)?.toDate(),
      maintenancePlanSizeBytes: (data['maintenancePlanSizeBytes'] as num?)?.toInt(),
      odometerKm: (data['odometerKm'] as num?)?.toDouble(),
      nextServiceKm: (data['nextServiceKm'] as num?)?.toDouble(),
      nextServiceDate: (data['nextServiceDate'] as Timestamp?)?.toDate(),
      lastServiceDate: (data['lastServiceDate'] as Timestamp?)?.toDate(),
      lastServiceNotes: data['lastServiceNotes'] as String?,
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

  List<({double lat, double lng})> _trailPointsFromData(dynamic raw) {
    if (raw is! List) return const [];
    final points = <({double lat, double lng})>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final lat = (item['lat'] as num?)?.toDouble() ?? (item['latitude'] as num?)?.toDouble();
      final lng = (item['lng'] as num?)?.toDouble() ?? (item['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      points.add((lat: lat, lng: lng));
    }
    return points;
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
      trailPoints: _trailPointsFromData(data['trailPoints']),
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
      destinationAddress: data['destinationAddress'] as String?,
      destinationLatitude: (data['destinationLatitude'] as num?)?.toDouble(),
      destinationLongitude: (data['destinationLongitude'] as num?)?.toDouble(),
      startedById: data['startedById'] as String?,
      startedByName: data['startedByName'] as String?,
      startedAt: (data['startedAt'] as Timestamp?)?.toDate(),
      routePoints: _trailPointsFromData(data['routePoints']),
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

  DriverIssueReport _driverIssueReportFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return DriverIssueReport(
      id: doc.id,
      driverId: data['driverId'] as String? ?? '',
      driverName: data['driverName'] as String? ?? 'Motorista',
      message: data['message'] as String? ?? '',
      vehicleId: data['vehicleId'] as String?,
      vehicleName: data['vehicleName'] as String?,
      adminReply: data['adminReply'] as String?,
      repliedAt: (data['repliedAt'] as Timestamp?)?.toDate(),
      repliedByName: data['repliedByName'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
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
        if (vehicle.stoppedLatitude != null) 'stoppedLatitude': vehicle.stoppedLatitude,
        if (vehicle.stoppedLongitude != null) 'stoppedLongitude': vehicle.stoppedLongitude,
        if (vehicle.maintenancePlanFileName != null) 'maintenancePlanFileName': vehicle.maintenancePlanFileName,
        if (vehicle.maintenancePlanUpdatedAt != null)
          'maintenancePlanUpdatedAt': Timestamp.fromDate(vehicle.maintenancePlanUpdatedAt!),
        if (vehicle.maintenancePlanSizeBytes != null) 'maintenancePlanSizeBytes': vehicle.maintenancePlanSizeBytes,
        if (vehicle.odometerKm != null) 'odometerKm': vehicle.odometerKm,
        if (vehicle.nextServiceKm != null) 'nextServiceKm': vehicle.nextServiceKm,
        if (vehicle.nextServiceDate != null) 'nextServiceDate': Timestamp.fromDate(vehicle.nextServiceDate!),
        if (vehicle.lastServiceDate != null) 'lastServiceDate': Timestamp.fromDate(vehicle.lastServiceDate!),
        if (vehicle.lastServiceNotes != null) 'lastServiceNotes': vehicle.lastServiceNotes,
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
      case 'too-many-requests':
        return 'Muitas tentativas. Aguarde 15–30 minutos ou teste outro dispositivo/rede.';
      default:
        return error.message ?? 'Erro de autenticacao.';
    }
  }
}