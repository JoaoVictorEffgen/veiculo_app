enum UserRole { driver, admin }

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
  });

  final String id;
  final String name;
  final String username;
  final UserRole role;
}
