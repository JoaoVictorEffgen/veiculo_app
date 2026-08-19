import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import 'local_vehicle_repository.dart';

final repositoryProvider = Provider<LocalVehicleRepository>((ref) => LocalVehicleRepository.instance);

class AuthController extends StateNotifier<AppUser?> {
  AuthController(this._repository) : super(null);
  final LocalVehicleRepository _repository;

  String? login(String email, String password) {
    final user = _repository.authenticate(email, password);
    if (user == null) return 'E-mail ou senha invalidos.';
    state = user;
    return null;
  }

  void logout() => state = null;
}

final authControllerProvider = StateNotifierProvider<AuthController, AppUser?>((ref) => AuthController(ref.watch(repositoryProvider)));

class VehicleController extends StateNotifier<List<Vehicle>> {
  VehicleController(this._repository) : super(_repository.vehicles);
  final LocalVehicleRepository _repository;

  void refresh() => state = _repository.vehicles;

  String? update(Vehicle vehicle) {
    try {
      _repository.updateVehicle(vehicle);
      refresh();
      return null;
    } on StateError catch (error) {
      return error.message;
    }
  }

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

final vehicleControllerProvider = StateNotifierProvider<VehicleController, List<Vehicle>>((ref) => VehicleController(ref.watch(repositoryProvider)));

class AdminController extends StateNotifier<int> {
  AdminController(this._repository) : super(0);
  final LocalVehicleRepository _repository;

  String? addVehicle(AppUser actor, {required String name, required String model, required String plate}) {
    try { _repository.addVehicle(actor, name: name, model: model, plate: plate); state++; return null; } on StateError catch (error) { return error.message; }
  }

  String? deleteVehicle(AppUser actor, String vehicleId) {
    try { _repository.deleteVehicle(actor, vehicleId); state++; return null; } on StateError catch (error) { return error.message; }
  }

  String? addDriver(AppUser actor, {required String name, required String email, required String password}) {
    try { _repository.addDriver(actor, name: name, email: email, password: password); state++; return null; } on StateError catch (error) { return error.message; }
  }

  String? deleteDriver(AppUser actor, String driverId) {
    try { _repository.deleteDriver(actor, driverId); state++; return null; } on StateError catch (error) { return error.message; }
  }
}

final adminControllerProvider = StateNotifierProvider<AdminController, int>((ref) => AdminController(ref.watch(repositoryProvider)));

final movementsProvider = Provider<List<Movement>>((ref) {
  ref.watch(vehicleControllerProvider);
  return ref.watch(repositoryProvider).movements;
});