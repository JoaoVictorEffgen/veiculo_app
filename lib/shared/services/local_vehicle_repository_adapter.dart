import 'dart:async';
import 'dart:typed_data';

import '../models/app_models.dart';
import 'local_vehicle_repository.dart';
import 'vehicle_repository.dart';

/// Adapta o repositório Drift local para a interface usada pelo app.
class LocalVehicleRepositoryAdapter implements VehicleRepository {
  LocalVehicleRepositoryAdapter(this._local) {
    _vehiclesController.add(_local.vehicles);
    _movementsController.add(_local.movements);
    _usersController.add(_local.users);
    _authController.add(_local.currentUser);
  }

  final LocalVehicleRepository _local;
  final _authController = StreamController<AppUser?>.broadcast();
  final _vehiclesController = StreamController<List<Vehicle>>.broadcast();
  final _movementsController = StreamController<List<Movement>>.broadcast();
  final _usersController = StreamController<List<AppUser>>.broadcast();

  void _sync() {
    _vehiclesController.add(_local.vehicles);
    _movementsController.add(_local.movements);
    _usersController.add(_local.users);
  }

  @override
  AppUser? get currentUser => _local.currentUser;

  @override
  Stream<AppUser?> get authStateChanges async* {
    yield _local.currentUser;
    yield* _authController.stream;
  }

  @override
  Future<String?> login(String email, String password) async {
    final user = _local.authenticate(email, password);
    if (user == null) return 'E-mail ou senha invalidos.';
    await _local.saveSession(user);
    _authController.add(user);
    return null;
  }

  @override
  Future<String?> sendPasswordResetEmail(String email) async {
    return 'Recuperacao de senha disponivel apenas com Firebase.';
  }

  @override
  Future<void> logout() async {
    await _local.clearSession();
    _authController.add(null);
  }

  @override
  Stream<List<Vehicle>> watchVehicles() => _vehiclesController.stream;

  @override
  Future<List<Vehicle>> fetchVehicles() async => _local.vehicles;

  @override
  Stream<List<Movement>> watchMovements() {
    return _movementsController.stream.map((movements) {
      final user = _local.currentUser;
      if (user == null) return const <Movement>[];
      if (user.role == UserRole.admin) return movements;
      return movements.where((movement) => movement.driverId == user.id).toList();
    });
  }

  @override
  Stream<List<AppUser>> watchUsers() {
    return _usersController.stream.map((users) {
      final user = _local.currentUser;
      if (user == null) return const <AppUser>[];
      if (user.role == UserRole.admin) return users;
      return users.where((item) => item.id == user.id).toList();
    });
  }

  @override
  Stream<List<DriverTrack>> watchDriverTracks() => Stream.value(const []);

  @override
  Stream<List<FleetAnnouncement>> watchAnnouncementsForUser(AppUser user) => Stream.value(const []);

  @override
  Future<String?> publishAnnouncement(
    AppUser actor, {
    required String message,
    DateTime? expiresAt,
    String? targetDriverId,
    String? targetDriverName,
  }) async =>
      'Disponivel apenas com Firebase.';

  @override
  Future<String?> deleteAnnouncement(AppUser actor, String announcementId) async => 'Disponivel apenas com Firebase.';

  @override
  Future<String?> respondToAnnouncement(
    AppUser driver,
    String announcementId,
    AnnouncementResponseStatus status, {
    String? rejectionReason,
  }) async =>
      'Disponivel apenas com Firebase.';

  @override
  Stream<List<FleetAdminAlert>> watchAdminAlerts() => Stream.value(const []);

  @override
  Future<void> markAdminAlertsViewed(AppUser admin) async {}

  @override
  Future<String?> submitDriverIssueReport(
    AppUser driver, {
    required String message,
    String? vehicleId,
    String? vehicleName,
  }) async =>
      'Disponivel apenas com Firebase.';

  @override
  Stream<List<DriverIssueReport>> watchDriverIssueReports(AppUser user) => Stream.value(const []);

  @override
  Future<String?> replyToDriverIssueReport(AppUser admin, String reportId, String reply) async =>
      'Disponivel apenas com Firebase.';

  @override
  Future<void> saveFcmToken(AppUser user, String token) async {}

  @override
  Future<VehicleChecklist?> getTodayChecklist(AppUser driver, String vehicleId) async => null;

  @override
  Future<String?> saveVehicleChecklist(
    AppUser driver,
    Vehicle vehicle, {
    required Map<String, bool> items,
    String? notes,
    required String signatureBase64,
  }) async =>
      'Disponivel apenas com Firebase.';

  @override
  Stream<List<VehicleChecklist>> watchTodayChecklistsForDriver(AppUser driver) => Stream.value(const []);

  @override
  Stream<List<VehicleChecklist>> watchVehicleChecklists(AppUser user) => Stream.value(const []);

  @override
  Future<String?> startVehicle(String vehicleId, AppUser user) async {
    try {
      _local.startVehicle(vehicleId, user);
      _sync();
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }

  @override
  Future<void> purgeOrphanedTracking(List<String> driverIds) async {}

  @override
  Future<String?> stopVehicle(String vehicleId, AppUser user, String location, {double? distanceKm, double? stoppedLatitude, double? stoppedLongitude}) async {
    try {
      _local.stopVehicle(vehicleId, user, location);
      _sync();
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }

  @override
  Future<String?> addVehicle(AppUser actor, {required String name, required String model, required String plate}) async {
    try {
      await _local.addVehicle(actor, name: name, model: model, plate: plate);
      _sync();
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }

  @override
  Future<String?> editVehicle(AppUser actor, {required String vehicleId, required String name, required String model, required String plate}) async {
    try {
      await _local.editVehicle(actor, vehicleId: vehicleId, name: name, model: model, plate: plate);
      _sync();
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }

  @override
  Future<String?> deleteVehicle(AppUser actor, String vehicleId) async {
    try {
      await _local.deleteVehicle(actor, vehicleId);
      _sync();
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }

  @override
  Future<String?> uploadMaintenancePlan(
    AppUser actor,
    String vehicleId,
    List<int> bytes,
    String fileName,
  ) async =>
      'Disponivel apenas com Firebase.';

  @override
  Future<String?> removeMaintenancePlan(AppUser actor, String vehicleId) async =>
      'Disponivel apenas com Firebase.';

  @override
  Future<Uint8List?> fetchMaintenancePlanBytes(String vehicleId) async => null;

  @override
  Future<String?> updateVehicleMaintenance(
    AppUser actor,
    String vehicleId, {
    double? odometerKm,
    double? nextServiceKm,
    DateTime? nextServiceDate,
    DateTime? lastServiceDate,
    String? lastServiceNotes,
  }) async =>
      'Disponivel apenas com Firebase.';

  @override
  Future<String?> addMaintenanceLog(
    AppUser actor,
    String vehicleId, {
    required DateTime serviceDate,
    required double odometerKm,
    required String serviceType,
    String? notes,
    double? cost,
  }) async =>
      'Disponivel apenas com Firebase.';

  @override
  Stream<List<MaintenanceLog>> watchMaintenanceLogs(String vehicleId) => Stream.value(const []);

  @override
  Future<String?> addDriver(AppUser actor, {required String name, required String email, required String password}) async {
    try {
      await _local.addDriver(actor, name: name, email: email, password: password);
      _sync();
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }

  @override
  Future<String?> editDriver(AppUser actor, {required String driverId, required String name, required String email, String? password}) async {
    try {
      await _local.editDriver(actor, driverId: driverId, name: name, email: email, password: password);
      _sync();
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }

  @override
  Future<String?> deleteDriver(AppUser actor, String driverId) async {
    try {
      await _local.deleteDriver(actor, driverId);
      _sync();
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }

  @override
  Future<void> ensureSeedData() async {}
}
