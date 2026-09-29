import '../models/app_models.dart';
import '../tenant/tenant_ids.dart';

/// Dados apenas para modo local (testes offline). Firebase usa "Criar empresa".
abstract final class AppSeedData {
  static const defaultPassword = '123456';

  static const users = [
    SeedUser(
      name: 'Joao Silva',
      email: 'motorista1@empresa.com',
      password: defaultPassword,
      role: UserRole.driver,
      companyId: TenantIds.defaultCompany,
    ),
    SeedUser(
      name: 'Administrador',
      email: 'admin@empresa.com',
      password: defaultPassword,
      role: UserRole.admin,
      companyId: TenantIds.defaultCompany,
    ),
  ];

  static List<Vehicle> get vehicles => const [
        Vehicle(
          id: 'vehicle-1',
          name: 'Strada 01',
          model: 'Fiat Strada',
          plate: 'ABC-1D23',
          status: VehicleStatus.stopped,
          stoppedLocation: 'Garagem',
        ),
      ];
}

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
