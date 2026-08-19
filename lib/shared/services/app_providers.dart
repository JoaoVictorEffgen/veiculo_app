import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import '../models/auth_session.dart';
import 'vehicle_repository.dart';

final repositoryProvider = Provider<VehicleRepository>((ref) {
  throw UnimplementedError('repositoryProvider must be overridden in main.dart');
});

class AuthController extends StateNotifier<AuthSession> {
  AuthController(this._repository) : super(const AuthSession.loading()) {
    _subscription = _repository.authStateChanges.listen((user) {
      state = AuthSession.ready(user);
    });
  }

  final VehicleRepository _repository;
  StreamSubscription<AppUser?>? _subscription;

  AppUser? get user => state.user;

  Future<String?> login(String email, String password) => _repository.login(email, password);

  Future<void> logout() => _repository.logout();

  @override
  void dispose() {
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

  Future<String?> stop(String vehicleId, AppUser user, String location) async {
    final error = await _repository.stopVehicle(vehicleId, user, location);
    if (error == null) await refresh();
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
