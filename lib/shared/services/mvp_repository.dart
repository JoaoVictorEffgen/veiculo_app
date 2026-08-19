import '../../features/auth/domain/entities/app_user.dart';
import '../../features/history/domain/entities/movement.dart';
import '../../features/vehicles/domain/entities/vehicle.dart';

class MvpRepository {
  MvpRepository()
      : _users = const [
          AppUser(id: 'driver-1', name: 'Joao', username: 'motorista1', role: UserRole.driver),
          AppUser(id: 'driver-2', name: 'Carlos', username: 'motorista2', role: UserRole.driver),
          AppUser(id: 'driver-3', name: 'Marcos', username: 'motorista3', role: UserRole.driver),
          AppUser(id: 'driver-4', name: 'Ana', username: 'motorista4', role: UserRole.driver),
          AppUser(id: 'admin-1', name: 'Administrador', username: 'admin', role: UserRole.admin),
        ],
        _vehicles = [
          const Vehicle(id: 'v1', name: 'Fiat Strada', code: '01', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
          const Vehicle(id: 'v2', name: 'Fiat Toro', code: '01', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
          const Vehicle(id: 'v3', name: 'Toyota Hilux', code: '01', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
          const Vehicle(id: 'v4', name: 'Chevrolet S10', code: '01', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
          const Vehicle(id: 'v5', name: 'Volkswagen Saveiro', code: '01', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
          const Vehicle(id: 'v6', name: 'Renault Oroch', code: '01', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
          const Vehicle(id: 'v7', name: 'Ford Ranger', code: '01', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
        ];

  final List<AppUser> _users;
  final List<Vehicle> _vehicles;
  final List<Movement> _movements = [];

  List<AppUser> get users => List.unmodifiable(_users);
  List<Vehicle> get vehicles => List.unmodifiable(_vehicles);
  List<Movement> get movements => List.unmodifiable(_movements.reversed);

  AppUser? authenticate(String username, String password) {
    if (password != '123456') return null;
    for (final user in _users) {
      if (user.username == username.trim().toLowerCase()) return user;
    }
    return null;
  }

  Vehicle startVehicle(String vehicleId, AppUser user) {
    final index = _vehicles.indexWhere((vehicle) => vehicle.id == vehicleId);
    final vehicle = _vehicles[index];
    if (vehicle.status == VehicleStatus.moving) {
      throw StateError('Veículo indisponível: ${vehicle.driverName} já está utilizando este veículo.');
    }
    final now = DateTime.now();
    final updated = vehicle.copyWith(
      status: VehicleStatus.moving,
      driverId: user.id,
      driverName: user.name,
      startedAt: now,
      stoppedLocation: null,
    );
    _vehicles[index] = updated;
    _movements.add(Movement(id: '${now.microsecondsSinceEpoch}', vehicleId: vehicle.id, vehicleName: vehicle.name, driverName: user.name, action: MovementAction.on, createdAt: now));
    return updated;
  }

  Vehicle stopVehicle(String vehicleId, AppUser user, String location) {
    final index = _vehicles.indexWhere((vehicle) => vehicle.id == vehicleId);
    final vehicle = _vehicles[index];
    if (vehicle.status == VehicleStatus.stopped) throw StateError('Este veículo já está parado.');
    if (vehicle.driverId != user.id) throw StateError('Somente o motorista responsável pode parar este veículo.');
    final now = DateTime.now();
    final updated = vehicle.copyWith(status: VehicleStatus.stopped, stoppedAt: now, stoppedLocation: location.trim());
    _vehicles[index] = updated;
    _movements.add(Movement(id: '${now.microsecondsSinceEpoch}', vehicleId: vehicle.id, vehicleName: vehicle.name, driverName: user.name, action: MovementAction.off, createdAt: now, location: location.trim()));
    return updated;
  }
}
