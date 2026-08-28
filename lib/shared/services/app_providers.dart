import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../models/auth_session.dart';
import '../models/fleet_analytics.dart';
import 'driver_track_filter.dart';
import 'fleet_analytics_service.dart';
import 'fleet_report_export_service.dart';
import 'maintenance_alert_service.dart';
import 'location_tracking_service.dart';
import 'login_preferences_service.dart';
import 'trip_start_voice_service.dart';
import 'vehicle_repository.dart';

final repositoryProvider = Provider<VehicleRepository>((ref) {
  throw UnimplementedError('repositoryProvider must be overridden in main.dart');
});

final loginPreferencesServiceProvider = Provider<LoginPreferencesService>((ref) => LoginPreferencesService());

final locationTrackingServiceProvider = Provider<LocationTrackingService>((ref) {
  throw UnimplementedError('locationTrackingServiceProvider must be overridden in main.dart');
});

final tripStartVoiceServiceProvider = Provider<TripStartVoiceService>((ref) {
  final service = TripStartVoiceService();
  ref.onDispose(service.dispose);
  return service;
});

class AuthController extends StateNotifier<AuthSession> {
  AuthController(this._repository) : super(const AuthSession.loading()) {
    _subscription = _repository.authStateChanges.listen(
      (user) {
        _bootstrapTimer?.cancel();
        state = AuthSession.ready(user);
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Erro no stream de autenticacao: $error');
        state = AuthSession.ready(_repository.currentUser);
      },
    );
    _bootstrapTimer = Timer(const Duration(seconds: 10), () {
      unawaited(_finishBootstrap());
    });
  }

  Future<void> _finishBootstrap() async {
    if (state.isReady) return;
    if (_repository.hasPersistedAuthSession) {
      final user = await _repository.restoreSessionIfNeeded();
      state = AuthSession.ready(user);
      return;
    }
    state = AuthSession.ready(_repository.currentUser);
  }

  final VehicleRepository _repository;
  StreamSubscription<AppUser?>? _subscription;
  Timer? _bootstrapTimer;

  AppUser? get user => state.user;

  Future<String?> login(String email, String password) async {
    final error = await _repository.login(email, password);
    state = AuthSession.ready(_repository.currentUser);
    return error;
  }

  Future<String?> sendPasswordResetEmail(String email) => _repository.sendPasswordResetEmail(email);

  Future<void> logout() => _repository.logout();

  @override
  void dispose() {
    _bootstrapTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthSession>((ref) {
  throw UnimplementedError('authControllerProvider must be overridden in main.dart');
});

class VehicleController extends StateNotifier<List<Vehicle>> {
  VehicleController._(this._repository) : super(const []);

  factory VehicleController.active(VehicleRepository repository) {
    final controller = VehicleController._(repository);
    controller._subscribe();
    return controller;
  }

  factory VehicleController.idle(VehicleRepository repository) => VehicleController._(repository);

  final VehicleRepository _repository;
  StreamSubscription<List<Vehicle>>? _subscription;
  bool _hasLoaded = false;

  bool get hasLoaded => _hasLoaded;

  void _subscribe() {
    _subscription?.cancel();
    _subscription = _repository.watchVehicles().listen(
      (vehicles) {
        _hasLoaded = true;
        state = vehicles;
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Erro no stream de veiculos: $error');
        _hasLoaded = true;
      },
    );
  }

  Future<void> refresh() async {
    state = await _repository.fetchVehicles();
  }

  Future<String?> start(String vehicleId, AppUser user) async {
    final error = await _repository.startVehicle(vehicleId, user);
    if (error == null) await refresh();
    return error;
  }

  Future<String?> stop(String vehicleId, AppUser user, String location, {double? distanceKm, double? stoppedLatitude, double? stoppedLongitude}) async {
    final error = await _repository.stopVehicle(
      vehicleId,
      user,
      location,
      distanceKm: distanceKm,
      stoppedLatitude: stoppedLatitude,
      stoppedLongitude: stoppedLongitude,
    );
    if (error == null) unawaited(refresh());
    return error;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final vehicleControllerProvider = StateNotifierProvider<VehicleController, List<Vehicle>>((ref) {
  final session = ref.watch(authControllerProvider);
  final repository = ref.watch(repositoryProvider);
  if (!session.isReady || session.user == null) {
    return VehicleController.idle(repository);
  }
  return VehicleController.active(repository);
});

class AdminController extends StateNotifier<int> {
  AdminController(this._repository) : super(0);

  final VehicleRepository _repository;

  Future<String?> addVehicle(AppUser actor, {required String name, required String model, required String plate}) async {
    final error = await _repository.addVehicle(actor, name: name, model: model, plate: plate);
    if (error == null) state++;
    return error;
  }

  Future<String?> editVehicle(
    AppUser actor, {
    required String vehicleId,
    required String name,
    required String model,
    required String plate,
  }) async {
    final error = await _repository.editVehicle(actor, vehicleId: vehicleId, name: name, model: model, plate: plate);
    if (error == null) state++;
    return error;
  }

  Future<String?> deleteVehicle(AppUser actor, String vehicleId) async {
    final error = await _repository.deleteVehicle(actor, vehicleId);
    if (error == null) state++;
    return error;
  }

  Future<String?> addDriver(AppUser actor, {required String name, required String email, required String password}) async {
    final error = await _repository.addDriver(actor, name: name, email: email, password: password);
    if (error == null) state++;
    return error;
  }

  Future<String?> editDriver(
    AppUser actor, {
    required String driverId,
    required String name,
    required String email,
    String? password,
  }) async {
    final error = await _repository.editDriver(actor, driverId: driverId, name: name, email: email, password: password);
    if (error == null) state++;
    return error;
  }

  Future<String?> deleteDriver(AppUser actor, String driverId) async {
    final error = await _repository.deleteDriver(actor, driverId);
    if (error == null) state++;
    return error;
  }

  Future<String?> uploadMaintenancePlan(
    AppUser actor,
    String vehicleId,
    List<int> bytes,
    String fileName,
  ) async {
    final error = await _repository.uploadMaintenancePlan(actor, vehicleId, bytes, fileName);
    if (error == null) state++;
    return error;
  }

  Future<String?> removeMaintenancePlan(AppUser actor, String vehicleId) async {
    final error = await _repository.removeMaintenancePlan(actor, vehicleId);
    if (error == null) state++;
    return error;
  }

  Future<String?> updateVehicleMaintenance(
    AppUser actor,
    String vehicleId, {
    double? odometerKm,
    double? nextServiceKm,
    DateTime? nextServiceDate,
    DateTime? lastServiceDate,
    String? lastServiceNotes,
  }) async {
    final error = await _repository.updateVehicleMaintenance(
      actor,
      vehicleId,
      odometerKm: odometerKm,
      nextServiceKm: nextServiceKm,
      nextServiceDate: nextServiceDate,
      lastServiceDate: lastServiceDate,
      lastServiceNotes: lastServiceNotes,
    );
    if (error == null) state++;
    return error;
  }

  Future<String?> addMaintenanceLog(
    AppUser actor,
    String vehicleId, {
    required DateTime serviceDate,
    required double odometerKm,
    required String serviceType,
    String? notes,
    double? cost,
  }) async {
    final error = await _repository.addMaintenanceLog(
      actor,
      vehicleId,
      serviceDate: serviceDate,
      odometerKm: odometerKm,
      serviceType: serviceType,
      notes: notes,
      cost: cost,
    );
    if (error == null) state++;
    return error;
  }
}

final adminControllerProvider = StateNotifierProvider<AdminController, int>((ref) {
  return AdminController(ref.watch(repositoryProvider));
});

final movementsProvider = StreamProvider<List<Movement>>((ref) {
  final user = ref.watch(authControllerProvider).user;
  if (user == null) return Stream.value(const []);
  ref.watch(adminControllerProvider);
  return ref.watch(repositoryProvider).watchMovements();
});

final usersProvider = StreamProvider<List<AppUser>>((ref) {
  final user = ref.watch(authControllerProvider).user;
  if (user == null) return Stream.value(const []);
  ref.watch(adminControllerProvider);
  return ref.watch(repositoryProvider).watchUsers();
});

final rawDriverTracksProvider = StreamProvider<List<DriverTrack>>((ref) {
  final user = ref.watch(authControllerProvider).user;
  if (user == null) return Stream.value(const []);
  return ref.watch(repositoryProvider).watchDriverTracks();
});

final driverTracksProvider = Provider<AsyncValue<List<DriverTrack>>>((ref) {
  final tracksAsync = ref.watch(rawDriverTracksProvider);
  final vehicles = ref.watch(vehicleControllerProvider);
  final users = ref.watch(usersProvider).valueOrNull ?? const <AppUser>[];
  return tracksAsync.when(
    data: (tracks) {
      final enriched = DriverTrackFilter.withLiveNames(tracks: tracks, users: users, vehicles: vehicles);
      return AsyncValue.data(DriverTrackFilter.forMapDisplay(enriched, vehicles));
    },
    loading: () => const AsyncValue.loading(),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
  );
});

final fleetAnnouncementsProvider = StreamProvider<List<FleetAnnouncement>>((ref) {
  final user = ref.watch(authControllerProvider).user;
  if (user == null) return Stream.value(const []);
  ref.watch(adminControllerProvider);
  return ref.watch(repositoryProvider).watchAnnouncementsForUser(user);
});

final adminAlertsProvider = StreamProvider<List<FleetAdminAlert>>((ref) {
  final user = ref.watch(authControllerProvider).user;
  if (user?.role != UserRole.admin) return Stream.value(const []);
  return ref.watch(repositoryProvider).watchAdminAlerts();
});

final driverIssueReportsProvider = StreamProvider<List<DriverIssueReport>>((ref) {
  final user = ref.watch(authControllerProvider).user;
  if (user == null) return Stream.value(const []);
  return ref.watch(repositoryProvider).watchDriverIssueReports(user);
});

final unreadAdminAlertsCountProvider = Provider<int>((ref) {
  final alerts = ref.watch(adminAlertsProvider).valueOrNull ?? const <FleetAdminAlert>[];
  return alerts.where((alert) => !alert.viewed).length;
});

final vehicleChecklistsProvider = StreamProvider<List<VehicleChecklist>>((ref) {
  final user = ref.watch(authControllerProvider).user;
  if (user == null) return Stream.value(const []);
  return ref.watch(repositoryProvider).watchVehicleChecklists(user);
});

final driverTodayChecklistsProvider = StreamProvider<List<VehicleChecklist>>((ref) {
  final user = ref.watch(authControllerProvider).user;
  if (user == null || !user.mustCompleteVehicleChecklist) return Stream.value(const []);
  return ref.watch(repositoryProvider).watchTodayChecklistsForDriver(user);
});

VehicleChecklist? todayChecklistForVehicle(WidgetRef ref, String vehicleId) {
  final checklists = ref.watch(driverTodayChecklistsProvider).valueOrNull;
  if (checklists == null) return null;
  for (final checklist in checklists) {
    if (checklist.vehicleId == vehicleId) return checklist;
  }
  return null;
}

final alertsPeriodProvider = StateProvider<FleetPeriodSelection>(
  (ref) => const FleetPeriodSelection(preset: FleetPeriodPreset.last30Days),
);

final fleetPeriodProvider = StateProvider<FleetPeriodSelection>(
  (ref) => const FleetPeriodSelection(preset: FleetPeriodPreset.last30Days),
);

final fleetAnalyticsServiceProvider = Provider<FleetAnalyticsService>((ref) => FleetAnalyticsService());

final fleetReportExportServiceProvider = Provider<FleetReportExportService>((ref) => FleetReportExportService());

final maintenanceAlertServiceProvider = Provider<MaintenanceAlertService>((ref) => MaintenanceAlertService());

final maintenanceAlertsProvider = Provider<List<MaintenanceAlert>>((ref) {
  final vehicles = ref.watch(vehicleControllerProvider);
  return ref.watch(maintenanceAlertServiceProvider).compute(vehicles);
});

final maintenanceLogsProvider = StreamProvider.family<List<MaintenanceLog>, String>((ref, vehicleId) {
  ref.watch(adminControllerProvider);
  return ref.watch(repositoryProvider).watchMaintenanceLogs(vehicleId);
});

final fleetAnalyticsProvider = Provider<AsyncValue<FleetAnalyticsReport>>((ref) {
  final user = ref.watch(authControllerProvider).user;
  if (user?.role != UserRole.admin) {
    return AsyncValue.error(StateError('Acesso negado'), StackTrace.current);
  }

  final period = ref.watch(fleetPeriodProvider);
  final movementsAsync = ref.watch(movementsProvider);
  final vehicles = ref.watch(vehicleControllerProvider);
  final usersAsync = ref.watch(usersProvider);
  final adminAlertsAsync = ref.watch(adminAlertsProvider);
  final driverReportsAsync = ref.watch(driverIssueReportsProvider);

  if (movementsAsync.isLoading || usersAsync.isLoading || adminAlertsAsync.isLoading || driverReportsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (movementsAsync.hasError) {
    return AsyncValue.error(movementsAsync.error!, movementsAsync.stackTrace ?? StackTrace.empty);
  }
  if (usersAsync.hasError) {
    return AsyncValue.error(usersAsync.error!, usersAsync.stackTrace ?? StackTrace.empty);
  }
  if (adminAlertsAsync.hasError) {
    return AsyncValue.error(adminAlertsAsync.error!, adminAlertsAsync.stackTrace ?? StackTrace.empty);
  }
  if (driverReportsAsync.hasError) {
    return AsyncValue.error(driverReportsAsync.error!, driverReportsAsync.stackTrace ?? StackTrace.empty);
  }

  final drivers = usersAsync.valueOrNull?.where((item) => item.role == UserRole.driver).toList() ?? [];
  final report = ref.read(fleetAnalyticsServiceProvider).compute(
        movements: movementsAsync.valueOrNull ?? const [],
        vehicles: vehicles,
        drivers: drivers,
        taskAlerts: adminAlertsAsync.valueOrNull ?? const [],
        driverReports: driverReportsAsync.valueOrNull ?? const [],
        periodSelection: period,
      );
  return AsyncValue.data(report);
});
