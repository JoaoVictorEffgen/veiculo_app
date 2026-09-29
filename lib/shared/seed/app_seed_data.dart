import '../models/app_models.dart';
import '../tenant/tenant_ids.dart';

class SeedUser {
  const SeedUser({
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    required this.companyId,
  });

  final String name;
  final String email;
  final String password;
  final UserRole role;
  final String companyId;
}

class SeedVehicle {
  const SeedVehicle({
    required this.id,
    required this.vehicle,
    required this.companyId,
  });

  final String id;
  final Vehicle vehicle;
  final String companyId;
}

class SeedCompany {
  const SeedCompany({required this.id, required this.name});

  final String id;
  final String name;
}

/// Dados iniciais — duas empresas isoladas para teste multi-tenant.
/// Senha padrao de todos: [defaultPassword]
abstract final class AppSeedData {
  static const defaultPassword = '123456';

  static const adminEmail = 'admin@empresa.com';
  static const demoAdminEmail = 'admin@demo.com';

  static const companies = [
    SeedCompany(id: TenantIds.defaultCompany, name: 'Empresa Principal'),
    SeedCompany(id: TenantIds.demoCompany, name: 'Empresa Demo (teste)'),
  ];

  static const users = [
    SeedUser(
      name: 'Joao Silva',
      email: 'motorista1@empresa.com',
      password: defaultPassword,
      role: UserRole.driver,
      companyId: TenantIds.defaultCompany,
    ),
    SeedUser(
      name: 'Carlos Santos',
      email: 'motorista2@empresa.com',
      password: defaultPassword,
      role: UserRole.driver,
      companyId: TenantIds.defaultCompany,
    ),
    SeedUser(
      name: 'Marina Costa',
      email: 'motorista3@empresa.com',
      password: defaultPassword,
      role: UserRole.driver,
      companyId: TenantIds.defaultCompany,
    ),
    SeedUser(
      name: 'Pedro Oliveira',
      email: 'motorista4@empresa.com',
      password: defaultPassword,
      role: UserRole.driver,
      companyId: TenantIds.defaultCompany,
    ),
    SeedUser(
      name: 'Administrador',
      email: adminEmail,
      password: defaultPassword,
      role: UserRole.admin,
      companyId: TenantIds.defaultCompany,
    ),
    SeedUser(
      name: 'Ana Demo',
      email: 'motorista1@demo.com',
      password: defaultPassword,
      role: UserRole.driver,
      companyId: TenantIds.demoCompany,
    ),
    SeedUser(
      name: 'Bruno Demo',
      email: 'motorista2@demo.com',
      password: defaultPassword,
      role: UserRole.driver,
      companyId: TenantIds.demoCompany,
    ),
    SeedUser(
      name: 'Admin Demo',
      email: demoAdminEmail,
      password: defaultPassword,
      role: UserRole.admin,
      companyId: TenantIds.demoCompany,
    ),
  ];

  static const seedVehicles = [
    SeedVehicle(
      id: 'vehicle-1',
      companyId: TenantIds.defaultCompany,
      vehicle: Vehicle(
        id: 'vehicle-1',
        name: 'Strada 01',
        model: 'Fiat Strada',
        plate: 'ABC-1D23',
        status: VehicleStatus.stopped,
        stoppedLocation: 'Garagem da empresa',
      ),
    ),
    SeedVehicle(
      id: 'vehicle-2',
      companyId: TenantIds.defaultCompany,
      vehicle: Vehicle(
        id: 'vehicle-2',
        name: 'Toro 01',
        model: 'Fiat Toro',
        plate: 'DEF-4G56',
        status: VehicleStatus.stopped,
        stoppedLocation: 'Garagem da empresa',
      ),
    ),
    SeedVehicle(
      id: 'vehicle-3',
      companyId: TenantIds.defaultCompany,
      vehicle: Vehicle(
        id: 'vehicle-3',
        name: 'Hilux',
        model: 'Toyota Hilux',
        plate: 'GHI-7J89',
        status: VehicleStatus.stopped,
        stoppedLocation: 'Garagem da empresa',
      ),
    ),
    SeedVehicle(
      id: 'vehicle-4',
      companyId: TenantIds.defaultCompany,
      vehicle: Vehicle(
        id: 'vehicle-4',
        name: 'Fiorino',
        model: 'Fiat Fiorino',
        plate: 'STU-9V01',
        status: VehicleStatus.stopped,
        stoppedLocation: 'Garagem da empresa',
      ),
    ),
    SeedVehicle(
      id: 'vehicle-demo-1',
      companyId: TenantIds.demoCompany,
      vehicle: Vehicle(
        id: 'vehicle-demo-1',
        name: 'Saveiro Demo',
        model: 'VW Saveiro',
        plate: 'DEM-0A01',
        status: VehicleStatus.stopped,
        stoppedLocation: 'Base Demo',
      ),
    ),
    SeedVehicle(
      id: 'vehicle-demo-2',
      companyId: TenantIds.demoCompany,
      vehicle: Vehicle(
        id: 'vehicle-demo-2',
        name: 'Ranger Demo',
        model: 'Ford Ranger',
        plate: 'DEM-0B02',
        status: VehicleStatus.stopped,
        stoppedLocation: 'Base Demo',
      ),
    ),
  ];

  /// Compatibilidade com codigo que ainda referencia a lista antiga.
  static List<Vehicle> get vehicles => seedVehicles.map((item) => item.vehicle).toList();
}
