import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import 'local_vehicle_repository.dart';

final repositoryProvider = Provider<LocalVehicleRepository>((ref) {
  throw UnimplementedError('repositoryProvider must be overridden in main.dart');
});

class AuthController extends StateNotifier<AppUser?> {
  AuthController(this._repository, {AppUser? initialUser}) : super(initialUser);

  final LocalVehicleRepository _repository;

  Future<String?> login(String email, String password) async {
    final user = _repository.authenticate(email, password);
    if (user == null) return 'E-mail ou senha invalidos.';
    await _repository.saveSession(user);
    state = user;
    return null;
  }

  Future<void> logout() async {
    await _repository.clearSession();
    state = null;
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AppUser?>((ref) {
  throw UnimplementedError('authControllerProvider must be overridden in main.dart');
});

class VehicleController extends StateNotifier<List<Vehicle>> {
  VehicleController(this._repository) : super(_repository.vehicles);

  final LocalVehicleRepository _repository;

  void refresh() => state = List.of(_repository.vehicles);

  String? start(String vehicleId, AppUser user) {
    try {
      _repository.startVehicle(vehicleId, user);
      refresh();
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }

  String? stop(String vehicleId, AppUser user, String location) {
    try {
      _repository.stopVehicle(vehicleId, user, location);
      refresh();
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }
}

final vehicleControllerProvider = StateNotifierProvider<VehicleController, List<Vehicle>>((ref) {
  return VehicleController(ref.watch(repositoryProvider));
});

class AdminController extends StateNotifier<int> {
  AdminController(this._repository) : super(0);

  final LocalVehicleRepository _repository;

  Future<String?> addVehicle(AppUser actor, {required String name, required String model, required String plate}) async {
    try {
      await _repository.addVehicle(actor, name: name, model: model, plate: plate);
      state++;
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }

  Future<String?> editVehicle(
    AppUser actor, {
    required String vehicleId,
    required String name,
    required String model,
    required String plate,
  }) async {
    try {
      await _repository.editVehicle(actor, vehicleId: vehicleId, name: name, model: model, plate: plate);
      state++;
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }

  Future<String?> deleteVehicle(AppUser actor, String vehicleId) async {
    try {
      await _repository.deleteVehicle(actor, vehicleId);
      state++;
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }

  Future<String?> addDriver(AppUser actor, {required String name, required String email, required String password}) async {
    try {
      await _repository.addDriver(actor, name: name, email: email, password: password);
      state++;
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }

  Future<String?> editDriver(
    AppUser actor, {
    required String driverId,
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      await _repository.editDriver(actor, driverId: driverId, name: name, email: email, password: password);
      state++;
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }

  Future<String?> deleteDriver(AppUser actor, String driverId) async {
    try {
      await _repository.deleteDriver(actor, driverId);
      state++;
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }
}

final adminControllerProvider = StateNotifierProvider<AdminController, int>((ref) {
  return AdminController(ref.watch(repositoryProvider));
});

final movementsProvider = Provider<List<Movement>>((ref) {
  ref.watch(vehicleControllerProvider);
  ref.watch(adminControllerProvider);
  return ref.watch(repositoryProvider).movements;
});

final usersProvider = Provider<List<AppUser>>((ref) {
  ref.watch(adminControllerProvider);
  return ref.watch(repositoryProvider).users;
});
