import '../models/app_models.dart';

class SeedUser {
  const SeedUser({
    required this.name,
    required this.email,
    required this.password,
    required this.role,
  });

  final String name;
  final String email;
  final String password;
  final UserRole role;
}

/// Dados iniciais para testes — 1 admin, 4 motoristas e 4 veiculos.
/// Senha padrao de todos: [defaultPassword]
abstract final class AppSeedData {
  static const defaultPassword = '123456';

  static const adminEmail = 'admin@empresa.com';

  static const users = [
    SeedUser(name: 'Joao Silva', email: 'motorista1@empresa.com', password: defaultPassword, role: UserRole.driver),
    SeedUser(name: 'Carlos Santos', email: 'motorista2@empresa.com', password: defaultPassword, role: UserRole.driver),
    SeedUser(name: 'Marina Costa', email: 'motorista3@empresa.com', password: defaultPassword, role: UserRole.driver),
    SeedUser(name: 'Pedro Oliveira', email: 'motorista4@empresa.com', password: defaultPassword, role: UserRole.driver),
    SeedUser(name: 'Administrador', email: adminEmail, password: defaultPassword, role: UserRole.admin),
  ];

  static const vehicles = [
    Vehicle(id: 'vehicle-1', name: 'Strada 01', model: 'Fiat Strada', plate: 'ABC-1D23', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
    Vehicle(id: 'vehicle-2', name: 'Toro 01', model: 'Fiat Toro', plate: 'DEF-4G56', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
    Vehicle(id: 'vehicle-3', name: 'Hilux', model: 'Toyota Hilux', plate: 'GHI-7J89', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
    Vehicle(id: 'vehicle-4', name: 'Fiorino', model: 'Fiat Fiorino', plate: 'STU-9V01', status: VehicleStatus.stopped, stoppedLocation: 'Garagem da empresa'),
  ];
}
