import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../../core/utils/date_formatter.dart';
import '../models/app_models.dart';
import '../seed/app_seed_data.dart';

const _sessionKey = 'current_user_id';

class LocalVehicleRepository {
  LocalVehicleRepository(this._db);

  final AppDatabase _db;

  static Future<LocalVehicleRepository> create({AppDatabase? database}) async {
    final repository = LocalVehicleRepository(database ?? AppDatabase());
    await repository._seedIfEmpty();
    return repository;
  }

  List<AppUser> _usersCache = [];
  List<Vehicle> _vehiclesCache = [];
  List<Movement> _movementsCache = [];
  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;
  List<AppUser> get users => List.unmodifiable(_usersCache);
  List<Vehicle> get vehicles => List.unmodifiable(_vehiclesCache);
  List<Movement> get movements => List.unmodifiable(_movementsCache);

  Future<void> loadAll() async {
    _usersCache = await _loadUsers();
    _vehiclesCache = await _loadVehicles();
    _movementsCache = await _loadMovements();
    final sessionId = await _readSessionId();
    _currentUser = sessionId == null
        ? null
        : _usersCache.where((user) => user.id == sessionId).firstOrNull;
  }

  Future<AppUser?> restoreSession() async {
    await loadAll();
    return _currentUser;
  }

  Future<void> _seedIfEmpty() async {
    final count = await _db.select(_db.users).get();
    if (count.isNotEmpty) {
      await loadAll();
      return;
    }

    final seedUsers = [
      for (var i = 0; i < AppSeedData.users.length; i++)
        AppUser(
          id: AppSeedData.users[i].role == UserRole.admin ? 'admin-1' : 'driver-${i + 1}',
          name: AppSeedData.users[i].name,
          email: AppSeedData.users[i].email,
          password: AppSeedData.users[i].password,
          role: AppSeedData.users[i].role,
        ),
    ];

    const seedVehicles = AppSeedData.vehicles;

    await _db.batch((batch) {
      for (final user in seedUsers) {
        batch.insert(_db.users, _userToRow(user));
      }
      for (final vehicle in seedVehicles) {
        batch.insert(_db.vehicles, _vehicleToRow(vehicle));
      }
    });

    await loadAll();
  }

  AppUser? authenticate(String email, String password) {
    for (final user in _usersCache) {
      if (user.email == email.trim().toLowerCase() && user.password == password) {
        return user;
      }
    }
    return null;
  }

  Future<AppUser?> saveSession(AppUser user) async {
    _currentUser = user;
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: _sessionKey, value: user.id),
        );
    return user;
  }

  Future<void> clearSession() async {
    _currentUser = null;
    await (_db.delete(_db.appSettings)..where((row) => row.key.equals(_sessionKey))).go();
  }

  Future<String?> _readSessionId() async {
    final row = await (_db.select(_db.appSettings)..where((item) => item.key.equals(_sessionKey))).getSingleOrNull();
    return row?.value;
  }

  void updateVehicle(Vehicle vehicle) {
    final index = _vehiclesCache.indexWhere((item) => item.id == vehicle.id);
    if (index < 0) throw StateError('Veiculo nao encontrado.');
    _vehiclesCache[index] = vehicle;
    _db.into(_db.vehicles).insertOnConflictUpdate(_vehicleToRow(vehicle));
  }

  Future<void> addVehicle(AppUser actor, {required String name, required String model, required String plate}) async {
    _requireAdmin(actor);
    if (_vehiclesCache.any((vehicle) => vehicle.plate.toLowerCase() == plate.trim().toLowerCase())) {
      throw StateError('Ja existe um veiculo com essa placa.');
    }
    final vehicle = Vehicle(
      id: 'vehicle-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      model: model.trim(),
      plate: plate.trim().toUpperCase(),
      status: VehicleStatus.stopped,
      stoppedLocation: 'Garagem da empresa',
    );
    _vehiclesCache.add(vehicle);
    await _db.into(_db.vehicles).insert(_vehicleToRow(vehicle));
  }

  Future<void> editVehicle(
    AppUser actor, {
    required String vehicleId,
    required String name,
    required String model,
    required String plate,
  }) async {
    _requireAdmin(actor);
    final index = _vehiclesCache.indexWhere((vehicle) => vehicle.id == vehicleId);
    if (index < 0) throw StateError('Veiculo nao encontrado.');
    if (_vehiclesCache.any((vehicle) => vehicle.id != vehicleId && vehicle.plate.toLowerCase() == plate.trim().toLowerCase())) {
      throw StateError('Ja existe um veiculo com essa placa.');
    }
    final updated = _vehiclesCache[index].copyWith(name: name.trim(), model: model.trim(), plate: plate.trim().toUpperCase());
    _vehiclesCache[index] = updated;
    await _db.into(_db.vehicles).insertOnConflictUpdate(_vehicleToRow(updated));
  }

  Future<void> deleteVehicle(AppUser actor, String vehicleId) async {
    _requireAdmin(actor);
    final index = _vehiclesCache.indexWhere((vehicle) => vehicle.id == vehicleId);
    if (index < 0) throw StateError('Veiculo nao encontrado.');
    if (_vehiclesCache[index].status == VehicleStatus.moving) {
      throw StateError('Nao e possivel excluir um veiculo em uso.');
    }
    _vehiclesCache.removeAt(index);
    await (_db.delete(_db.vehicles)..where((row) => row.id.equals(vehicleId))).go();
  }

  Future<void> addDriver(AppUser actor, {required String name, required String email, required String password}) async {
    _requireAdmin(actor);
    if (_usersCache.any((user) => user.email.toLowerCase() == email.trim().toLowerCase())) {
      throw StateError('Ja existe um usuario com esse e-mail.');
    }
    final user = AppUser(
      id: 'driver-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      email: email.trim().toLowerCase(),
      password: password,
      role: UserRole.driver,
    );
    _usersCache.add(user);
    await _db.into(_db.users).insert(_userToRow(user));
  }

  Future<void> editDriver(
    AppUser actor, {
    required String driverId,
    required String name,
    required String email,
    String? password,
  }) async {
    _requireAdmin(actor);
    final index = _usersCache.indexWhere((user) => user.id == driverId && user.role == UserRole.driver);
    if (index < 0) throw StateError('Motorista nao encontrado.');
    if (_usersCache.any((user) => user.id != driverId && user.email.toLowerCase() == email.trim().toLowerCase())) {
      throw StateError('Ja existe um usuario com esse e-mail.');
    }
    final current = _usersCache[index];
    final updated = AppUser(
      id: driverId,
      name: name.trim(),
      email: email.trim().toLowerCase(),
      password: password == null || password.isEmpty ? current.password : password,
      role: UserRole.driver,
    );
    _usersCache[index] = updated;
    await _db.into(_db.users).insertOnConflictUpdate(_userToRow(updated));
  }

  Future<void> deleteDriver(AppUser actor, String driverId) async {
    _requireAdmin(actor);
    final index = _usersCache.indexWhere((user) => user.id == driverId && user.role == UserRole.driver);
    if (index < 0) throw StateError('Motorista nao encontrado.');
    if (_vehiclesCache.any((vehicle) => vehicle.currentDriverId == driverId)) {
      throw StateError('Nao e possivel excluir um motorista que esta usando um veiculo.');
    }
    _usersCache.removeAt(index);
    await (_db.delete(_db.users)..where((row) => row.id.equals(driverId))).go();
  }

  Vehicle startVehicle(String vehicleId, AppUser user) {
    final index = _vehiclesCache.indexWhere((vehicle) => vehicle.id == vehicleId);
    if (index < 0) throw StateError('Veiculo nao encontrado.');
    final current = _vehiclesCache[index];
    if (current.status == VehicleStatus.moving) {
      final since = formatTime(current.startedAt);
      throw StateError('Veiculo indisponivel: ${current.name} esta em uso por ${current.currentDriverName} desde $since.');
    }
    final now = DateTime.now();
    final updated = current.copyWith(
      status: VehicleStatus.moving,
      currentDriverId: user.id,
      currentDriverName: user.name,
      startedAt: now,
      stoppedAt: null,
      stoppedLocation: null,
    );
    _vehiclesCache[index] = updated;
    _persistVehicle(updated);
    _persistMovement(
      Movement(
        id: '$vehicleId-${now.microsecondsSinceEpoch}',
        vehicleId: vehicleId,
        vehicleName: current.name,
        driverId: user.id,
        driverName: user.name,
        action: MovementAction.on,
        createdAt: now,
      ),
    );
    return updated;
  }

  Vehicle stopVehicle(String vehicleId, AppUser user, String location) {
    final index = _vehiclesCache.indexWhere((vehicle) => vehicle.id == vehicleId);
    if (index < 0) throw StateError('Veiculo nao encontrado.');
    final current = _vehiclesCache[index];
    if (current.status == VehicleStatus.stopped) throw StateError('Este veiculo ja esta parado.');
    if (current.currentDriverId != user.id) {
      throw StateError('Somente o motorista responsavel pode parar o veiculo.');
    }
    final now = DateTime.now();
    final updated = Vehicle(
      id: current.id,
      name: current.name,
      model: current.model,
      plate: current.plate,
      status: VehicleStatus.stopped,
      stoppedAt: now,
      stoppedLocation: location.trim(),
    );
    _vehiclesCache[index] = updated;
    _persistVehicle(updated);
    _persistMovement(
      Movement(
        id: '$vehicleId-${now.microsecondsSinceEpoch}',
        vehicleId: vehicleId,
        vehicleName: current.name,
        driverId: current.currentDriverId ?? user.id,
        driverName: current.currentDriverName ?? user.name,
        action: MovementAction.off,
        createdAt: now,
        location: location.trim(),
      ),
    );
    return updated;
  }

  void _requireAdmin(AppUser actor) {
    if (actor.role != UserRole.admin) throw StateError('Somente administradores podem alterar cadastros.');
  }

  void _persistVehicle(Vehicle vehicle) {
    _db.into(_db.vehicles).insertOnConflictUpdate(_vehicleToRow(vehicle));
  }

  void _persistMovement(Movement movement) {
    _movementsCache.insert(0, movement);
    _db.into(_db.movements).insert(_movementToRow(movement));
  }

  Future<List<AppUser>> _loadUsers() async {
    final rows = await _db.select(_db.users).get();
    return rows.map(_userFromRow).toList();
  }

  Future<List<Vehicle>> _loadVehicles() async {
    final rows = await _db.select(_db.vehicles).get();
    return rows.map(_vehicleFromRow).toList();
  }

  Future<List<Movement>> _loadMovements() async {
    final rows = await (_db.select(_db.movements)..orderBy([(row) => OrderingTerm.desc(row.createdAt)])).get();
    return rows.map(_movementFromRow).toList();
  }

  UsersCompanion _userToRow(AppUser user) => UsersCompanion.insert(
        id: user.id,
        name: user.name,
        email: user.email,
        password: user.password,
        role: user.role.name,
      );

  AppUser _userFromRow(UserRow row) => AppUser(
        id: row.id,
        name: row.name,
        email: row.email,
        password: row.password,
        role: UserRole.values.byName(row.role),
      );

  VehiclesCompanion _vehicleToRow(Vehicle vehicle) => VehiclesCompanion.insert(
        id: vehicle.id,
        name: vehicle.name,
        model: vehicle.model,
        plate: vehicle.plate,
        status: vehicle.status.name,
        currentDriverId: Value(vehicle.currentDriverId),
        currentDriverName: Value(vehicle.currentDriverName),
        startedAt: Value(vehicle.startedAt),
        stoppedAt: Value(vehicle.stoppedAt),
        stoppedLocation: Value(vehicle.stoppedLocation),
      );

  Vehicle _vehicleFromRow(VehicleRow row) => Vehicle(
        id: row.id,
        name: row.name,
        model: row.model,
        plate: row.plate,
        status: VehicleStatus.values.byName(row.status),
        currentDriverId: row.currentDriverId,
        currentDriverName: row.currentDriverName,
        startedAt: row.startedAt,
        stoppedAt: row.stoppedAt,
        stoppedLocation: row.stoppedLocation,
      );

  MovementsCompanion _movementToRow(Movement movement) => MovementsCompanion.insert(
        id: movement.id,
        vehicleId: movement.vehicleId,
        vehicleName: movement.vehicleName,
        driverId: movement.driverId,
        driverName: movement.driverName,
        action: movement.action.name,
        createdAt: movement.createdAt,
        location: Value(movement.location),
      );

  Movement _movementFromRow(MovementRow row) => Movement(
        id: row.id,
        vehicleId: row.vehicleId,
        vehicleName: row.vehicleName,
        driverId: row.driverId,
        driverName: row.driverName,
        action: MovementAction.values.byName(row.action),
        createdAt: row.createdAt,
        location: row.location,
      );
}
