enum MovementAction { on, off }

class Movement {
  const Movement({
    required this.id,
    required this.vehicleId,
    required this.vehicleName,
    required this.driverName,
    required this.action,
    required this.createdAt,
    this.location,
  });

  final String id;
  final String vehicleId;
  final String vehicleName;
  final String driverName;
  final MovementAction action;
  final DateTime createdAt;
  final String? location;
}
