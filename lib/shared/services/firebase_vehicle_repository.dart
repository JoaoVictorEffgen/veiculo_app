import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import '../../core/utils/iterable_extensions.dart';
import '../firebase/firestore_paths.dart';
import '../models/app_models.dart';
import '../seed/app_seed_data.dart';
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
  Future<void>? _seedInFlight;
  bool _loginInFlight = false;

  static const _seedUsers = AppSeedData.users;
  static const _seedVehicles = AppSeedData.vehicles;

  Stream<List<T>> _signedInQueryStream<T>({
    required String debugLabel,
    required Stream<List<T>> Function() build,
  }) {
    if (_auth.currentUser == null) {
      return Stream.value(const []);
    }

    StreamSubscription<List<T>>? subscription;
    final controller = StreamController<List<T>>();

    controller.onListen = () {
      controller.add(const []);
      subscription = build().listen(
        controller.add,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('$debugLabel: $error');
          controller.add(const []);
        },
      );
    };

    controller.onCancel = () => subscription?.cancel();

    return controller.stream;
  }

  bool get _isAdminSession => _cachedUser?.role == UserRole.admin;

  @override
  AppUser? get currentUser => _cachedUser;

  @override
  Stream<AppUser?> get authStateChanges {
    return _auth.authStateChanges().asyncExpand((firebaseUser) {
      if (firebaseUser == null) {
        _cachedUser = null;
        return Stream.value(null);
      }

      final email = firebaseUser.email?.trim().toLowerCase() ?? '';
      final uid = firebaseUser.uid;

      Stream<AppUser?> listenProfile() {
        return _firestore.collection(FirestorePaths.users).doc(uid).snapshots().map((doc) {
          if (doc.exists) {
            final data = doc.data()!;
            final profileEmail = (data['email'] as String?)?.trim().toLowerCase() ?? '';
            if (_shouldLogoutForEmailChange(authEmail: email, profileEmail: profileEmail)) {
              debugPrint('Perfil: e-mail alterado pelo admin — encerrando sessao.');
              unawaited(_auth.signOut());
              _cachedUser = null;
              return null;
            }
            _cachedUser = _userFromDoc(doc);
            return _cachedUser!;
          }
          final fallback = _appUserFromSeed(uid, email);
          if (fallback != null) _cachedUser = fallback;
          return _cachedUser;
        }).transform(
          StreamTransformer<AppUser?, AppUser?>.fromHandlers(
            handleError: (error, stackTrace, sink) {
              debugPrint('authStateChanges profile: $error');
              final fallback = _cachedUser ?? _appUserFromSeed(uid, email);
              if (fallback != null) sink.add(fallback);
            },
          ),
        );
      }

      if (_cachedUser?.id == uid) {
        return Stream.value(_cachedUser).asyncExpand((_) => listenProfile());
      }

      final seedFallback = _appUserFromSeed(uid, email);
      if (seedFallback != null) {
        _cachedUser = seedFallback;
        return Stream.value(seedFallback).asyncExpand((_) => listenProfile());
      }

      return listenProfile();
    });
  }

  @override
  Future<String?> login(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();
    _loginInFlight = true;
    try {
      final credential = await _signIn(normalizedEmail, password);
      if (credential == null) {
        return 'Nao foi possivel entrar. Verifique e-mail e senha.';
      }

      final profileError = await _resolveUserAfterLogin(credential.user!, normalizedEmail);
      if (profileError != null) return profileError;

      if (_cachedUser!.role == UserRole.admin) {
        unawaited(
          _ensureAdminFleetReady().timeout(const Duration(seconds: 15)).then((_) {}).catchError((Object error) {
            debugPrint('Login admin: sync frota em background: $error');
          }),
        );
      }

      return null;
    } on FirebaseAuthException catch (error) {
      return _authErrorMessage(error);
    } on TimeoutException {
      return 'Tempo esgotado ao entrar. Verifique a conexao e tente novamente.';
    } finally {
      _loginInFlight = false;
    }
  }

  Future<UserCredential?> _signIn(String normalizedEmail, String password) async {
    try {
      return await _auth
          .signInWithEmailAndPassword(email: normalizedEmail, password: password)
          .timeout(const Duration(seconds: 12));
    } on FirebaseAuthException catch (error) {
      if (error.code != 'user-not-found' || !_isSeedEmail(normalizedEmail)) {
        rethrow;
      }

      debugPrint('Login: usuario seed ausente no Auth — criando conta.');
      try {
        await _ensureSeedAuthUser(normalizedEmail).timeout(const Duration(seconds: 12));
      } on TimeoutException {
        throw TimeoutException('seed-auth');
      }

      return await _auth
          .signInWithEmailAndPassword(email: normalizedEmail, password: password)
          .timeout(const Duration(seconds: 12));
    }
  }

  Future<void> _ensureSeedAuthUser(String normalizedEmail) async {
    final seed = _seedUsers.where((item) => item.email.trim().toLowerCase() == normalizedEmail).firstOrNull;
    if (seed == null) return;

    final secondaryApp = await _createSecondaryApp();
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      await _ensureAuthUserWithSecondary(secondaryAuth, FirebaseFirestore.instanceFor(app: secondaryApp), seed);
    } finally {
      await secondaryApp.delete();
    }
  }

  Future<String?> _resolveUserAfterLogin(User firebaseUser, String normalizedEmail) async {
    final uid = firebaseUser.uid;

    if (_isSeedEmail(normalizedEmail)) {
      _cachedUser = _appUserFromSeed(uid, normalizedEmail);
      if (_cachedUser != null) {
        unawaited(_syncUserProfileAfterLogin(uid, normalizedEmail));
        return null;
      }
    }

    try {
      final profile = await _loadAppUser(uid).timeout(const Duration(seconds: 4));
      if (profile != null) {
        _cachedUser = profile;
      }
    } on TimeoutException {
      debugPrint('Login: Firestore lento — usando perfil em cache.');
    } catch (error) {
      debugPrint('Login: erro ao carregar perfil: $error');
    }

    if (_cachedUser == null) {
      return 'Usuario sem cadastro no sistema.';
    }

    unawaited(_syncUserProfileAfterLogin(uid, normalizedEmail));
    return null;
  }

  Future<void> _syncUserProfileAfterLogin(String uid, String normalizedEmail) async {
    try {
      if (_isSeedEmail(normalizedEmail)) {
        await _repairSeedUserProfile(uid, normalizedEmail);
      }
      final profile = await _loadAppUser(uid, preferServer: true).timeout(const Duration(seconds: 8));
      if (profile != null) {
        _cachedUser = profile;
      }
    } catch (error) {
      debugPrint('Sync perfil pos-login: $error');
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
  Future<AppUser?> restorePersistedSession() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;
    if (_cachedUser?.id == firebaseUser.uid) return _cachedUser;

    final email = firebaseUser.email?.trim().toLowerCase() ?? '';
    if (_isSeedEmail(email)) {
      _cachedUser = _appUserFromSeed(firebaseUser.uid, email);
    }

    try {
      final loaded = await _loadAppUser(firebaseUser.uid).timeout(const Duration(seconds: 4));
      if (loaded != null) {
        _cachedUser = loaded;
      }
    } on TimeoutException {
      debugPrint('restorePersistedSession: Firestore lento.');
    }

    return _cachedUser;
  }

  @override
  Stream<List<Vehicle>> watchVehicles() {
    return _signedInQueryStream(
      debugLabel: 'watchVehicles',
      build: () => _firestore.collection(FirestorePaths.vehicles).snapshots().map((snapshot) {
        final vehicles = snapshot.docs.map(_vehicleFromDoc).toList();
        vehicles.sort((a, b) => a.name.compareTo(b.name));
        return vehicles;
      }),
    );
  }

  @override
  Future<List<Vehicle>> fetchVehicles() async {
    if (_auth.currentUser == null) return const [];
    final snapshot = await _firestore.collection(FirestorePaths.vehicles).orderBy('name').get();
    return snapshot.docs.map(_vehicleFromDoc).toList();
  }

  @override
  Stream<List<Movement>> watchMovements() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const <Movement>[]);

    return _signedInQueryStream(
      debugLabel: 'watchMovements',
      build: () {
        final query = _isAdminSession
            ? _firestore.collection(FirestorePaths.movements)
            : _firestore.collection(FirestorePaths.movements).where('driverId', isEqualTo: uid);
        return query.snapshots().map((snapshot) {
          final movements = snapshot.docs.map(_movementFromDoc).toList();
          movements.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return movements;
        });
      },
    );
  }

  @override
  Stream<List<AppUser>> watchUsers() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const <AppUser>[]);

    return _signedInQueryStream(
      debugLabel: 'watchUsers',
      build: () {
        if (_isAdminSession) {
          return _firestore.collection(FirestorePaths.users).snapshots().map((snapshot) {
            final users = snapshot.docs.map(_userFromDoc).toList();
            users.sort((a, b) => a.name.compareTo(b.name));
            return users;
          });
        }
        return _firestore.collection(FirestorePaths.users).doc(uid).snapshots().map(
              (snapshot) => snapshot.exists ? [_userFromDoc(snapshot)] : const <AppUser>[],
            );
      },
    );
  }

  @override
  Stream<List<DriverTrack>> watchDriverTracks() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const <DriverTrack>[]);

    return _signedInQueryStream(
      debugLabel: 'watchDriverTracks',
      build: () {
        if (_isAdminSession) {
          return _firestore.collection(FirestorePaths.tracking).snapshots().map(
                (snapshot) => snapshot.docs.map(_trackFromDoc).toList(),
              );
        }
        return _firestore.collection(FirestorePaths.tracking).doc(uid).snapshots().map(
              (snapshot) => snapshot.exists ? [_trackFromDoc(snapshot)] : const <DriverTrack>[],
            );
      },
    );
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
    return _signedInQueryStream(
      debugLabel: 'watchAdminAlerts',
      build: () => _firestore
          .collection(FirestorePaths.adminAlerts)
          .snapshots()
          .map((snapshot) {
        final alerts = snapshot.docs.map(_adminAlertFromDoc).toList();
        alerts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return alerts;
      }),
    );
  }

  @override
  Future<void> markAdminAlertsViewed(AppUser admin) async {
    if (admin.role != UserRole.admin) return;

    final unreadAlerts = await _firestore
        .collection(FirestorePaths.adminAlerts)
        .where('viewed', isEqualTo: false)
        .get();

    final unreadReports = await _firestore
        .collection(FirestorePaths.driverReports)
        .where('viewed', isEqualTo: false)
        .get();

    if (unreadAlerts.docs.isEmpty && unreadReports.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in unreadAlerts.docs) {
      batch.update(doc.reference, {
        'viewed': true,
        'viewedAt': FieldValue.serverTimestamp(),
      });
    }
    for (final doc in unreadReports.docs) {
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

    final authUid = _auth.currentUser?.uid;
    if (authUid == null) return 'Sessao expirada. Faca login novamente.';
    if (authUid != driver.id) return 'Sessao invalida. Faca login novamente.';

    try {
      await _firestore.collection(FirestorePaths.driverReports).add({
        'driverId': authUid,
        'driverName': driver.name,
        'message': trimmed,
        if (vehicleId != null) 'vehicleId': vehicleId,
        if (vehicleName != null) 'vehicleName': vehicleName,
        'viewed': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return null;
    } on FirebaseException catch (error) {
      return error.message ?? 'Erro ao enviar relato.';
    }
  }

  @override
  Stream<List<DriverIssueReport>> watchDriverIssueReports(AppUser user) {
    if (_auth.currentUser == null) {
      return Stream.value(const <DriverIssueReport>[]);
    }

    final query = user.role == UserRole.admin
        ? _firestore.collection(FirestorePaths.driverReports)
        : _firestore.collection(FirestorePaths.driverReports).where('driverId', isEqualTo: user.id);

    return _signedInQueryStream(
      debugLabel: 'watchDriverIssueReports',
      build: () => query.snapshots().map((snapshot) {
        final reports = snapshot.docs.map(_driverIssueReportFromDoc).toList();
        reports.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return reports;
      }),
    );
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
        'replyViewed': false,
      });
      return null;
    } on FirebaseException catch (error) {
      return error.message ?? 'Erro ao enviar resposta.';
    }
  }

  @override
  Future<void> markDriverReportRepliesViewed(AppUser driver) async {
    if (driver.role != UserRole.driver) return;

    final reports = await _firestore
        .collection(FirestorePaths.driverReports)
        .where('driverId', isEqualTo: driver.id)
        .get();

    final pending = reports.docs.where((doc) {
      final data = doc.data();
      final hasReply = (data['adminReply'] as String? ?? '').trim().isNotEmpty;
      if (!hasReply) return false;
      return data['replyViewed'] != true;
    });

    if (pending.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in pending) {
      batch.update(doc.reference, {'replyViewed': true});
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

    return _signedInQueryStream(
      debugLabel: 'watchTodayChecklistsForDriver',
      build: () => _firestore
          .collection(FirestorePaths.vehicleChecklists)
          .where('driverId', isEqualTo: driver.id)
          .where('checklistDate', isEqualTo: checklistDateKey())
          .snapshots()
          .map((snapshot) => snapshot.docs.map(_checklistFromDoc).toList()),
    );
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
      final existing = await docRef.get(const GetOptions(source: Source.server));
      if (existing.exists) {
        return 'Checklist deste veiculo ja foi feito hoje.';
      }

      final profile = await _loadAppUser(authUser.uid, preferServer: true);
      final driverName = profile?.name ?? driver.name;

      await docRef.set({
        'driverId': driver.id,
        'driverName': driverName,
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
      return null;
    } on FirebaseException catch (error) {
      return _friendlyFirestoreError(error, 'salvar checklist');
    } catch (error) {
      debugPrint('saveVehicleChecklist: $error');
      return 'Erro ao salvar checklist. Verifique a conexao e tente novamente.';
    }
  }

  @override
  Stream<List<VehicleChecklist>> watchVehicleChecklists(AppUser user) {
    if (_auth.currentUser == null) {
      return Stream.value(const <VehicleChecklist>[]);
    }

    final query = user.role == UserRole.admin
        ? _firestore.collection(FirestorePaths.vehicleChecklists)
        : _firestore
            .collection(FirestorePaths.vehicleChecklists)
            .where('driverId', isEqualTo: user.id);

    return _signedInQueryStream(
      debugLabel: 'watchVehicleChecklists',
      build: () => query.snapshots().map((snapshot) {
        final checklists = snapshot.docs.map(_checklistFromDoc).toList();
        checklists.sort((a, b) => b.completedAt.compareTo(a.completedAt));
        return checklists;
      }),
    );
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
          'stoppedLatitude': FieldValue.delete(),
          'stoppedLongitude': FieldValue.delete(),
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
    final accessError = await _requireFirestoreAdmin(actor);
    if (accessError != null) return accessError;
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
      return _friendlyFirestoreError(error, 'criar veiculo');
    }
  }

  String _friendlyFirestoreError(FirebaseException error, String action) {
    if (error.code == 'permission-denied') {
      return 'Sem permissao para $action. Saia e entre com admin@empresa.com (senha 123456).';
    }
    return error.message ?? 'Erro ao $action.';
  }

  Future<String?> _requireFirestoreAdmin(AppUser actor) async {
    if (actor.role != UserRole.admin) return 'Somente administradores podem alterar cadastros.';

    final uid = _auth.currentUser?.uid;
    if (uid == null || uid != actor.id) return 'Sessao invalida. Entre novamente.';

    if (_isSeedEmail(actor.email.trim().toLowerCase())) {
      await _repairSeedUserProfile(uid, actor.email.trim().toLowerCase());
    }

    final doc = await _firestore.collection(FirestorePaths.users).doc(uid).get(const GetOptions(source: Source.server));
    if (!doc.exists || doc.data()?['role'] != UserRole.admin.name) {
      return 'Perfil admin ausente no Firestore. Saia e entre com admin@empresa.com (senha 123456).';
    }
    return null;
  }

  @override
  Future<String?> editVehicle(AppUser actor, {required String vehicleId, required String name, required String model, required String plate}) async {
    final accessError = await _requireFirestoreAdmin(actor);
    if (accessError != null) return accessError;
    try {
      final trimmedName = name.trim();
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
    final accessError = await _requireFirestoreAdmin(actor);
    if (accessError != null) return accessError;

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
      return _friendlyFirestoreError(error, 'anexar plano de manutencao');
    } catch (error) {
      debugPrint('uploadMaintenancePlan: $error');
      return 'Erro ao anexar plano de manutencao. Tente um PDF menor ou verifique a conexao.';
    }
  }

  @override
  Future<String?> removeMaintenancePlan(AppUser actor, String vehicleId) async {
    final accessError = await _requireFirestoreAdmin(actor);
    if (accessError != null) return accessError;

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
      return _friendlyFirestoreError(error, 'remover plano de manutencao');
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
    final accessError = await _requireFirestoreAdmin(actor);
    if (accessError != null) return accessError;

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
      return _friendlyFirestoreError(error, 'salvar manutencao');
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
    final accessError = await _requireFirestoreAdmin(actor);
    if (accessError != null) return accessError;

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
    final accessError = await _requireFirestoreAdmin(actor);
    if (accessError != null) return accessError;
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
      return _friendlyFirestoreError(error, 'cadastrar motorista');
    }
  }

  @override
  Future<String?> editDriver(AppUser actor, {required String driverId, required String name, required String email, String? password}) async {
    final accessError = await _requireFirestoreAdmin(actor);
    if (accessError != null) return accessError;

    try {
      final driverDoc = await _firestore.collection(FirestorePaths.users).doc(driverId).get();
      if (!driverDoc.exists) return 'Motorista nao encontrado.';
      final currentEmail = (driverDoc.data()?['email'] as String? ?? '').trim().toLowerCase();
      final normalizedEmail = email.trim().toLowerCase();

      await _firestore.collection(FirestorePaths.users).doc(driverId).update({
        'name': name.trim(),
        'email': normalizedEmail,
      });

      unawaited(_propagateDriverProfileChange(
        driverId: driverId,
        name: name.trim(),
      ));

      final authError = await _updateDriverAuthIfSeed(
        currentEmail: currentEmail,
        newEmail: normalizedEmail,
        newPassword: password,
      );
      if (authError != null) return authError;

      if (_cachedUser?.id == driverId) {
        final doc = await _firestore.collection(FirestorePaths.users).doc(driverId).get(const GetOptions(source: Source.server));
        if (doc.exists) _cachedUser = _userFromDoc(doc);
      }

      return null;
    } on FirebaseException catch (error) {
      return _friendlyFirestoreError(error, 'atualizar motorista');
    }
  }

  Future<String?> _updateDriverAuthIfSeed({
    required String currentEmail,
    required String newEmail,
    required String? newPassword,
  }) async {
    if (newPassword == null && currentEmail == newEmail) return null;

    final seed = _seedUsers.where((item) => item.email.trim().toLowerCase() == currentEmail).firstOrNull;
    if (seed == null) {
      if (newPassword != null && newPassword.isNotEmpty) {
        return 'Senha alterada apenas em contas seed de teste. Use recuperacao por e-mail.';
      }
      return null;
    }

    final secondaryApp = await _createSecondaryApp();
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      await secondaryAuth.signInWithEmailAndPassword(
        email: currentEmail,
        password: seed.password,
      );
      final user = secondaryAuth.currentUser;
      if (user == null) return 'Nao foi possivel atualizar credenciais do motorista.';

      if (newPassword != null && newPassword.isNotEmpty) {
        await user.updatePassword(newPassword);
      }
      if (currentEmail != newEmail) {
        await user.verifyBeforeUpdateEmail(newEmail);
      }
      return null;
    } on FirebaseAuthException catch (error) {
      return _authErrorMessage(error);
    } finally {
      await secondaryApp.delete();
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
    if (_seedInFlight != null) {
      await _seedInFlight;
      return;
    }

    _seedInFlight = _runSeedData();
    try {
      await _seedInFlight;
    } finally {
      _seedInFlight = null;
    }
  }

  Future<void> _runSeedData() async {
    if (_loginInFlight) {
      debugPrint('Seed adiado: login em andamento.');
      return;
    }
    await _ensureSeedViaSecondaryApp();
    if (_loginInFlight) return;

    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return;

    final email = firebaseUser.email?.trim().toLowerCase() ?? '';
    final isAdmin = _cachedUser?.role == UserRole.admin ||
        email == AppSeedData.adminEmail.trim().toLowerCase();
    if (!isAdmin) return;

    await _ensureAdminFleetReady();
  }

  Future<void> _ensureSeedViaSecondaryApp() async {
    final secondaryApp = await _createSecondaryApp();
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final secondaryFirestore = FirebaseFirestore.instanceFor(app: secondaryApp);

      final adminSeed = _seedUsers.firstWhere((seed) => seed.role == UserRole.admin);
      await _ensureAuthUserWithSecondary(secondaryAuth, secondaryFirestore, adminSeed);

      final adminCredential = await secondaryAuth.signInWithEmailAndPassword(
        email: adminSeed.email.trim().toLowerCase(),
        password: adminSeed.password,
      );
      final adminUid = adminCredential.user!.uid;
      await secondaryFirestore.collection(FirestorePaths.users).doc(adminUid).set({
        'name': adminSeed.name,
        'email': adminSeed.email.trim().toLowerCase(),
        'role': adminSeed.role.name,
      }, SetOptions(merge: true));

      for (final seed in _seedUsers) {
        await _ensureAuthUserWithSecondary(secondaryAuth, secondaryFirestore, seed);
      }

      await secondaryAuth.signInWithEmailAndPassword(
        email: adminSeed.email.trim().toLowerCase(),
        password: adminSeed.password,
      );

      var createdVehicles = 0;
      for (final vehicle in _seedVehicles) {
        final ref = secondaryFirestore.collection(FirestorePaths.vehicles).doc(vehicle.id);
        final snap = await ref.get();
        if (snap.exists) continue;
        try {
          await ref.set(_vehicleToMap(vehicle));
          createdVehicles++;
        } on FirebaseException catch (error) {
          debugPrint('Seed secundario: falha ao criar ${vehicle.id}: ${error.message}');
        }
      }
      if (createdVehicles > 0) {
        debugPrint('Seed Firebase (secundario): $createdVehicles veiculo(s) de teste criado(s).');
      }
    } catch (error, stackTrace) {
      debugPrint('Seed Firebase (secundario): $error\n$stackTrace');
    } finally {
      await secondaryApp.delete();
    }
  }

  /// Garante perfil admin no Firestore, remove duplicatas e cria veiculos seed
  /// usando a sessao primaria (admin ja autenticado).
  Future<String?> _ensureAdminFleetReady() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;

    final email = firebaseUser.email?.trim().toLowerCase() ?? '';
    if (!_isSeedEmail(email) && _cachedUser?.role != UserRole.admin) return null;

    if (_cachedUser?.role != UserRole.admin) {
      final loaded = await _loadAppUser(firebaseUser.uid, preferServer: true);
      if (loaded?.role != UserRole.admin) return null;
      _cachedUser = loaded;
    }

    await _repairSeedUserProfile(firebaseUser.uid, email.isNotEmpty ? email : AppSeedData.adminEmail);
    await _deduplicateSeedUsersAsAdmin();
    await _ensureSeedUserProfilesAsAdmin();
    await _ensureSeedVehiclesWithPrimarySession();

    final adminDoc = await _firestore
        .collection(FirestorePaths.users)
        .doc(firebaseUser.uid)
        .get(const GetOptions(source: Source.server));
    if (!adminDoc.exists || adminDoc.data()?['role'] != UserRole.admin.name) {
      return 'Nao foi possivel sincronizar o perfil admin. Tente sair e entrar de novo.';
    }

    return null;
  }

  Future<void> _ensureSeedVehiclesWithPrimarySession() async {
    var created = 0;
    for (final vehicle in _seedVehicles) {
      final ref = _firestore.collection(FirestorePaths.vehicles).doc(vehicle.id);
      final snap = await ref.get();
      if (snap.exists) continue;
      try {
        await ref.set(_vehicleToMap(vehicle));
        created++;
      } on FirebaseException catch (error) {
        debugPrint('Seed primario: falha ao criar ${vehicle.id}: ${error.message}');
      }
    }
    if (created > 0) {
      debugPrint('Seed primario: $created veiculo(s) de teste criado(s).');
    }
  }

  Future<void> _ensureSeedUserProfilesAsAdmin() async {
    final secondaryApp = await _createSecondaryApp();
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      for (final seed in _seedUsers) {
        final normalizedEmail = seed.email.trim().toLowerCase();
        String uid;
        try {
          final credential = await secondaryAuth.signInWithEmailAndPassword(
            email: normalizedEmail,
            password: seed.password,
          );
          uid = credential.user!.uid;
        } catch (error) {
          debugPrint('Seed perfis: nao foi possivel obter uid de $normalizedEmail: $error');
          continue;
        }

        final ref = _firestore.collection(FirestorePaths.users).doc(uid);
        final existing = await ref.get();
        if (existing.exists) continue;

        try {
          await ref.set({
            'name': seed.name,
            'email': normalizedEmail,
            'role': seed.role.name,
          });
          debugPrint('Seed perfis: criado perfil Firestore para $normalizedEmail');
        } on FirebaseException catch (error) {
          debugPrint('Seed perfis: falha ao criar $normalizedEmail: ${error.message}');
        }
      }
    } catch (error, stackTrace) {
      debugPrint('Seed perfis: $error\n$stackTrace');
    } finally {
      await secondaryApp.delete();
    }
  }

  Future<void> _deduplicateSeedUsersAsAdmin() async {
    final snapshot = await _firestore.collection(FirestorePaths.users).get();
    final byEmail = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in snapshot.docs) {
      final email = (doc.data()['email'] as String?)?.trim().toLowerCase();
      if (email == null || !_isSeedEmail(email)) continue;
      byEmail.putIfAbsent(email, () => []).add(doc);
    }

    final secondaryApp = await _createSecondaryApp();
    try {
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      for (final entry in byEmail.entries) {
        if (entry.value.length <= 1) continue;

        final seed = _seedUsers.firstWhere((item) => item.email.trim().toLowerCase() == entry.key);
        String? canonicalUid;
        try {
          final credential = await secondaryAuth.signInWithEmailAndPassword(
            email: entry.key,
            password: seed.password,
          );
          canonicalUid = credential.user!.uid;
        } catch (error) {
          debugPrint('Dedup usuarios: uid canonico indisponivel para ${entry.key}: $error');
          continue;
        }

        for (final doc in entry.value) {
          if (doc.id == canonicalUid) continue;
          try {
            await doc.reference.delete();
            debugPrint('Dedup usuarios: removido doc duplicado ${doc.id} (${entry.key})');
          } on FirebaseException catch (error) {
            debugPrint('Dedup usuarios: falha ao remover ${doc.id}: ${error.message}');
          }
        }

        final canonicalRef = _firestore.collection(FirestorePaths.users).doc(canonicalUid);
        final canonicalSnap = await canonicalRef.get();
        if (!canonicalSnap.exists) {
          await canonicalRef.set({
            'name': seed.name,
            'email': entry.key,
            'role': seed.role.name,
          });
        }
      }
    } catch (error, stackTrace) {
      debugPrint('Dedup usuarios: $error\n$stackTrace');
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
        email: seed.email.trim().toLowerCase(),
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
        email: seed.email.trim().toLowerCase(),
        password: seed.password,
      );
      uid = credential.user!.uid;
    }

    final ref = secondaryFirestore.collection(FirestorePaths.users).doc(uid);
    final existing = await ref.get();
    if (existing.exists) return;

    if (seed.role == UserRole.admin) {
      await secondaryAuth.signInWithEmailAndPassword(
        email: seed.email.trim().toLowerCase(),
        password: seed.password,
      );
      await ref.set({
        'name': seed.name,
        'email': seed.email,
        'role': seed.role.name,
      });
      return;
    }

    final adminSeed = _seedUsers.firstWhere((item) => item.role == UserRole.admin);
    await secondaryAuth.signInWithEmailAndPassword(
      email: adminSeed.email.trim().toLowerCase(),
      password: adminSeed.password,
    );
    await ref.set({
      'name': seed.name,
      'email': seed.email,
      'role': seed.role.name,
    });
  }

  bool _isSeedEmail(String normalizedEmail) {
    return _seedUsers.any((seed) => seed.email.trim().toLowerCase() == normalizedEmail);
  }

  bool _shouldLogoutForEmailChange({required String authEmail, required String profileEmail}) {
    if (authEmail.isEmpty || profileEmail.isEmpty) return false;
    return authEmail.trim().toLowerCase() != profileEmail.trim().toLowerCase();
  }

  Future<void> _propagateDriverProfileChange({required String driverId, required String name}) async {
    try {
      final vehicles = await _firestore.collection(FirestorePaths.vehicles).where('currentDriverId', isEqualTo: driverId).get();
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
      final tracks = await _firestore.collection(FirestorePaths.tracking).where('vehicleId', isEqualTo: vehicleId).get();
      for (final doc in tracks.docs) {
        await doc.reference.update({'vehicleName': name});
      }
    } catch (error) {
      debugPrint('Sync nome veiculo: $error');
    }
  }

  AppUser? _appUserFromSeed(String uid, String normalizedEmail) {
    final seed = _seedUsers.where((item) => item.email.trim().toLowerCase() == normalizedEmail).firstOrNull;
    if (seed == null) return null;
    return AppUser(
      id: uid,
      name: seed.name,
      email: normalizedEmail,
      password: '',
      role: seed.role,
    );
  }

  Future<bool> _repairSeedUserProfile(String uid, String normalizedEmail) async {
    final seed = _seedUsers.where((item) => item.email.trim().toLowerCase() == normalizedEmail).firstOrNull;
    if (seed == null) return false;

    final ref = _firestore.collection(FirestorePaths.users).doc(uid);
    final data = {
      'name': seed.name,
      'email': seed.email.trim().toLowerCase(),
      'role': seed.role.name,
    };

    try {
      final snap = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
      if (!snap.exists) {
        await ref.set(data).timeout(const Duration(seconds: 6));
        return true;
      }
      return false;
    } on TimeoutException {
      debugPrint('Falha ao reparar perfil seed: tempo esgotado.');
      return false;
    } on FirebaseException catch (error) {
      debugPrint('Falha ao reparar perfil do usuario seed: ${error.message}');
      return false;
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

  Future<AppUser?> _loadAppUser(String uid, {bool preferServer = false}) async {
    if (!preferServer && !kIsWeb) {
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
    }

    try {
      final remote = await _firestore
          .collection(FirestorePaths.users)
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
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
      viewed: data['viewed'] as bool? ?? false,
      replyViewed: data['replyViewed'] as bool? ?? (data['adminReply'] as String? ?? '').trim().isEmpty,
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
        return 'E-mail ou senha invalidos. Contas de teste: admin@empresa.com ou motorista1@empresa.com — senha 123456.';
      case 'operation-not-allowed':
        return 'Login por e-mail desativado no Firebase Console.';
      case 'email-already-in-use':
        return 'Ja existe um usuario com esse e-mail.';
      default:
        return error.message ?? 'Erro de autenticacao.';
    }
  }
}