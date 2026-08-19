enum VehicleStatus { moving, stopped }

class Vehicle {
  const Vehicle({
    required this.id,
    required this.name,
    required this.code,
    required this.status,
    this.driverId,
    this.driverName,
    this.startedAt,
    this.stoppedAt,
    this.stoppedLocation,
  });

  final String id;
  final String name;
  final String code;
  final VehicleStatus status;
  final String? driverId;
  final String? driverName;
  final DateTime? startedAt;
  final DateTime? stoppedAt;
  final String? stoppedLocation;

  Vehicle copyWith({
    VehicleStatus? status,
    String? driverId,
    String? driverName,
    DateTime? startedAt,
    DateTime? stoppedAt,
    String? stoppedLocation,
  }) {
    return Vehicle(
      id: id,
      name: name,
      code: code,
      status: status ?? this.status,
      driverId: driverId ?? this.driverId,
      driverName: driverName ?? this.driverName,
      startedAt: startedAt ?? this.startedAt,
      stoppedAt: stoppedAt ?? this.stoppedAt,
      stoppedLocation: stoppedLocation ?? this.stoppedLocation,
    );
  }
}
