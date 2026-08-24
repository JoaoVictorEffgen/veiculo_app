import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../models/auth_session.dart';
import '../models/fleet_analytics.dart';
import 'driver_track_filter.dart';
import 'fleet_analytics_service.dart';
import 'location_tracking_service.dart';
import 'login_preferences_service.dart';
import 'vehicle_repository.dart';

final repositoryProvider = Provider<VehicleRepository>((ref) {
  throw UnimplementedError('repositoryProvider must be overridden in main.dart');
});

final loginPreferencesServiceProvider = Provider<LoginPreferencesService>((ref) => LoginPreferencesService());

final locationTrackingServiceProvider = Provider<LocationTrackingService>((ref) {
  throw UnimplementedError('locationTrackingServiceProvider must be overridden in main.dart');
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
    _bootstrapTimer = Timer(const Duration(seconds: 8), () {
      if (!state.isReady) {
        debugPrint('Timeout de autenticacao — liberando app com sessao em cache.');
        state = AuthSession.ready(_repository.currentUser);
      }
    });
  }

  final VehicleRepository _repository;
  StreamSubscription<AppUser?>? _subscription;
  Timer? _bootstrapTimer;

  AppUser? get user => state.user;

  Future<String?> login(String email, String password) => _repository.login(email, password);

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
  VehicleController(this._repository) : super(const []) {
    _subscription = _repository.watchVehicles().listen(
      (vehicles) => state = vehicles,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Erro no stream de veiculos: $error');
      },
    );
  }

  final VehicleRepository _repository;
  StreamSubscription<List<Vehicle>>? _subscription;

  Future<void> refresh() async {
    state = await _repository.fetchVehicles();
  }

  Future<String?> start(String vehicleId, AppUser user) async {
    final error = await _repository.startVehicle(vehicleId, user);
    if (error == null) await refresh();
    return error;
  }

  Future<String?> stop(String vehicleId, AppUser user, String location, {double? distanceKm}) async {
    final error = await _repository.stopVehicle(vehicleId, user, location, distanceKm: distanceKm);
    // O stream watchVehicles() ja atualiza a UI; refresh bloqueante aqui
    // mantinha o dialogo "Registrando parada..." aberto no celular.
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
  return VehicleController(ref.watch(repositoryProvider));
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
}

final adminControllerProvider = StateNotifierProvider<AdminController, int>((ref) {
  return AdminController(ref.watch(repositoryProvider));
});

final movementsProvider = StreamProvider<List<Movement>>((ref) {
  ref.watch(adminControllerProvider);
  return ref.watch(repositoryProvider).watchMovements();
});

final usersProvider = StreamProvider<List<AppUser>>((ref) {
  ref.watch(adminControllerProvider);
  return ref.watch(repositoryProvider).watchUsers();
});

final rawDriverTracksProvider = StreamProvider<List<DriverTrack>>((ref) {
  return ref.watch(repositoryProvider).watchDriverTracks();
});

final driverTracksProvider = StreamProvider<List<DriverTrack>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return _activeDriverTracksStream(repo);
});

Stream<List<DriverTrack>> _activeDriverTracksStream(VehicleRepository repo) {
  final controller = StreamController<List<DriverTrack>>();
  var tracks = const <DriverTrack>[];
  var vehicles = const <Vehicle>[];
  var tracksReady = false;
  var vehiclesReady = false;

  void publish() {
    if (!controller.isClosed && (tracksReady || vehiclesReady)) {
      controller.add(DriverTrackFilter.activeOnly(tracks, vehicles));
    }
  }

  late final StreamSubscription<List<DriverTrack>> tracksSub;
  late final StreamSubscription<List<Vehicle>> vehiclesSub;

  controller.add(const []);

  tracksSub = repo.watchDriverTracks().listen(
        (value) {
          tracks = value;
          tracksReady = true;
          publish();
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Erro no stream de rastreamento: $error');
          tracks = const [];
          tracksReady = true;
          publish();
        },
      );

  vehiclesSub = repo.watchVehicles().listen(
        (value) {
          vehicles = value;
          vehiclesReady = true;
          publish();
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Erro no stream de veiculos (GPS): $error');
          vehicles = const [];
          vehiclesReady = true;
          publish();
        },
      );

  controller.onCancel = () async {
    await tracksSub.cancel();
    await vehiclesSub.cancel();
  };

  return controller.stream;
}

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

final fleetPeriodProvider = StateProvider<FleetPeriodSelection>(
  (ref) => const FleetPeriodSelection(preset: FleetPeriodPreset.last30Days),
);

final fleetAnalyticsServiceProvider = Provider<FleetAnalyticsService>((ref) => FleetAnalyticsService());

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

  if (movementsAsync.isLoading || usersAsync.isLoading || adminAlertsAsync.isLoading) {
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

  final drivers = usersAsync.valueOrNull?.where((item) => item.role == UserRole.driver).toList() ?? [];
  final report = ref.read(fleetAnalyticsServiceProvider).compute(
        movements: movementsAsync.valueOrNull ?? const [],
        vehicles: vehicles,
        drivers: drivers,
        taskAlerts: adminAlertsAsync.valueOrNull ?? const [],
        periodSelection: period,
      );
  return AsyncValue.data(report);
});
