import 'dart:async';

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
  Stream<AppUser?> get authStateChanges => _authController.stream;

  @override
  Future<String?> login(String email, String password) async {
    final user = _local.authenticate(email, password);
    if (user == null) return 'E-mail ou senha invalidos.';
    await _local.saveSession(user);
    _authController.add(user);
    return null;
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
  Stream<List<Movement>> watchMovements() => _movementsController.stream;

  @override
  Stream<List<AppUser>> watchUsers() => _usersController.stream;

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
  Future<String?> stopVehicle(String vehicleId, AppUser user, String location) async {
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
  Future<String?> editDriver(AppUser actor, {required String driverId, required String name, required String email, required String password}) async {
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
