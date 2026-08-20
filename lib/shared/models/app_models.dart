enum UserRole { driver, admin }

enum VehicleStatus { moving, stopped }

enum MovementAction { on, off }

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
    required this.role,
  });

  final String id;
  final String name;
  final String email;
  final String password;
  final UserRole role;
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.name,
    required this.model,
    required this.plate,
    required this.status,
    this.currentDriverId,
    this.currentDriverName,
    this.startedAt,
    this.stoppedAt,
    this.stoppedLocation,
  });

  final String id;
  final String name;
  final String model;
  final String plate;
  final VehicleStatus status;
  final String? currentDriverId;
  final String? currentDriverName;
  final DateTime? startedAt;
  final DateTime? stoppedAt;
  final String? stoppedLocation;

  Vehicle copyWith({
    String? name,
    String? model,
    String? plate,
    VehicleStatus? status,
    String? currentDriverId,
    String? currentDriverName,
    DateTime? startedAt,
    DateTime? stoppedAt,
    String? stoppedLocation,
  }) {
    return Vehicle(
      id: id,
      name: name ?? this.name,
      model: model ?? this.model,
      plate: plate ?? this.plate,
      status: status ?? this.status,
      currentDriverId: currentDriverId ?? this.currentDriverId,
      currentDriverName: currentDriverName ?? this.currentDriverName,
      startedAt: startedAt ?? this.startedAt,
      stoppedAt: stoppedAt ?? this.stoppedAt,
      stoppedLocation: stoppedLocation ?? this.stoppedLocation,
    );
  }
}

class Movement {
  const Movement({
    required this.id,
    required this.vehicleId,
    required this.vehicleName,
    required this.driverId,
    required this.driverName,
    required this.action,
    required this.createdAt,
    this.location,
  });

  final String id;
  final String vehicleId;
  final String vehicleName;
  final String driverId;
  final String driverName;
  final MovementAction action;
  final DateTime createdAt;
  final String? location;
}

class DriverTrack {
  const DriverTrack({
    required this.driverId,
    required this.driverName,
    required this.vehicleId,
    required this.vehicleName,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.updatedAt,
    this.accuracy,
    this.heading,
  });

  final String driverId;
  final String driverName;
  final String vehicleId;
  final String vehicleName;
  final double latitude;
  final double longitude;
  final double speedKmh;
  final DateTime updatedAt;
  final double? accuracy;
  final double? heading;
}