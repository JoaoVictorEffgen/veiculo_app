import '../models/app_models.dart';

class LocalVehicleRepository {
  LocalVehicleRepository._();

  static final instance = LocalVehicleRepository._();

  final List<AppUser> _users = [
    const AppUser(
      id: 'driver-1',
      name: 'Joao Silva',
      email: 'motorista1@empresa.com',
      password: '123456',
      role: UserRole.driver,
    ),
    const AppUser(
      id: 'driver-2',
      name: 'Carlos Santos',
      email: 'motorista2@empresa.com',
      password: '123456',
      role: UserRole.driver,
    ),
    const AppUser(
      id: 'driver-3',
      name: 'Marina Costa',
      email: 'motorista3@empresa.com',
      password: '123456',
      role: UserRole.driver,
    ),
    const AppUser(
      id: 'driver-4',
      name: 'Pedro Oliveira',
      email: 'motorista4@empresa.com',
      password: '123456',
      role: UserRole.driver,
    ),
    const AppUser(
      id: 'admin-1',
      name: 'Administrador',
      email: 'admin@empresa.com',
      password: '123456',
      role: UserRole.admin,
    ),
  ];

  final List<Vehicle> _vehicles = [
    const Vehicle(id: 'vehicle-1', name: 'Strada 01', model: 'Fiat Strada', plate: 'ABC-1D23', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
    const Vehicle(id: 'vehicle-2', name: 'Toro 01', model: 'Fiat Toro', plate: 'DEF-4G56', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
    const Vehicle(id: 'vehicle-3', name: 'Hilux', model: 'Toyota Hilux', plate: 'GHI-7J89', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
    const Vehicle(id: 'vehicle-4', name: 'Saveiro', model: 'VW Saveiro', plate: 'JKL-0M12', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
    const Vehicle(id: 'vehicle-5', name: 'Ranger', model: 'Ford Ranger', plate: 'MNO-3P45', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
    const Vehicle(id: 'vehicle-6', name: 'Master', model: 'Renault Master', plate: 'PQR-6S78', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
    const Vehicle(id: 'vehicle-7', name: 'Fiorino', model: 'Fiat Fiorino', plate: 'STU-9V01', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
  ];

  final List<Movement> _movements = [];

  List<AppUser> get users => List.unmodifiable(_users);
  List<Vehicle> get vehicles => List.unmodifiable(_vehicles);

  List<Movement> get movements => List.unmodifiable(_movements.reversed.toList(growable: false));

  void updateVehicle(Vehicle vehicle) {
    final index = _vehicles.indexWhere((item) => item.id == vehicle.id);
    if (index < 0) throw StateError('Veiculo nao encontrado.');
    _vehicles[index] = vehicle;
  }

  void addVehicle(AppUser actor, {required String name, required String model, required String plate}) {
    _requireAdmin(actor);
    if (_vehicles.any((vehicle) => vehicle.plate.toLowerCase() == plate.trim().toLowerCase())) {
      throw StateError('Ja existe um veiculo com essa placa.');
    }
    final id = 'vehicle-${DateTime.now().microsecondsSinceEpoch}';
    _vehicles.add(Vehicle(id: id, name: name.trim(), model: model.trim(), plate: plate.trim().toUpperCase(), status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'));
  }

  void deleteVehicle(AppUser actor, String vehicleId) {
    _requireAdmin(actor);
    final index = _vehicles.indexWhere((vehicle) => vehicle.id == vehicleId);
    if (index < 0) throw StateError('Veiculo nao encontrado.');
    if (_vehicles[index].status == VehicleStatus.moving) throw StateError('Nao e possivel excluir um veiculo em uso.');
    _vehicles.removeAt(index);
  }

  void addDriver(AppUser actor, {required String name, required String email, required String password}) {
    _requireAdmin(actor);
    if (_users.any((user) => user.email.toLowerCase() == email.trim().toLowerCase())) {
      throw StateError('Ja existe um usuario com esse e-mail.');
    }
    _users.add(AppUser(id: 'driver-${DateTime.now().microsecondsSinceEpoch}', name: name.trim(), email: email.trim().toLowerCase(), password: password, role: UserRole.driver));
  }

  void deleteDriver(AppUser actor, String driverId) {
    _requireAdmin(actor);
    final index = _users.indexWhere((user) => user.id == driverId && user.role == UserRole.driver);
    if (index < 0) throw StateError('Motorista nao encontrado.');
    if (_vehicles.any((vehicle) => vehicle.currentDriverId == driverId)) throw StateError('Nao e possivel excluir um motorista que esta usando um veiculo.');
    _users.removeAt(index);
  }

  void _requireAdmin(AppUser actor) {
    if (actor.role != UserRole.admin) throw StateError('Somente administradores podem alterar cadastros.');
  }

  AppUser? authenticate(String email, String password) {
    for (final user in _users) {
      if (user.email == email.trim().toLowerCase() && user.password == password) return user;
    }
    return null;
  }

  Vehicle startVehicle(String vehicleId, AppUser user) {
    final index = _vehicles.indexWhere((vehicle) => vehicle.id == vehicleId);
    if (index < 0) throw StateError('Veiculo nao encontrado.');
    final current = _vehicles[index];
    if (current.status == VehicleStatus.moving) throw StateError('${current.name} esta em uso por ${current.currentDriverName}.');
    final now = DateTime.now();
    final updated = current.copyWith(status: VehicleStatus.moving, currentDriverId: user.id, currentDriverName: user.name, startedAt: now);
    _vehicles[index] = updated;
    _movements.add(Movement(id: '$vehicleId-${now.microsecondsSinceEpoch}', vehicleId: vehicleId, vehicleName: current.name, driverId: user.id, driverName: user.name, action: MovementAction.on, createdAt: now));
    return updated;
  }

  Vehicle stopVehicle(String vehicleId, AppUser user, String location) {
    final index = _vehicles.indexWhere((vehicle) => vehicle.id == vehicleId);
    if (index < 0) throw StateError('Veiculo nao encontrado.');
    final current = _vehicles[index];
    if (current.status == VehicleStatus.stopped) throw StateError('Este veiculo ja esta parado.');
    if (current.currentDriverId != user.id && user.role != UserRole.admin) throw StateError('Somente o motorista responsavel pode parar o veiculo.');
    final now = DateTime.now();
    final updated = current.copyWith(status: VehicleStatus.stopped, stoppedAt: now, stoppedLocation: location.trim());
    _vehicles[index] = updated;
    _movements.add(Movement(id: '$vehicleId-${now.microsecondsSinceEpoch}', vehicleId: vehicleId, vehicleName: current.name, driverId: current.currentDriverId ?? user.id, driverName: current.currentDriverName ?? user.name, action: MovementAction.off, createdAt: now, location: location.trim()));
    return updated;
  }
}