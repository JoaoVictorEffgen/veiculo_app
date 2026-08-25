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

  bool get mustCompleteVehicleChecklist => role == UserRole.driver || role == UserRole.admin;

  bool get canRespondToFleetTasks => role == UserRole.driver;
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
    this.maintenancePlanFileName,
    this.maintenancePlanUpdatedAt,
    this.maintenancePlanSizeBytes,
    this.odometerKm,
    this.nextServiceKm,
    this.nextServiceDate,
    this.lastServiceDate,
    this.lastServiceNotes,
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
  final String? maintenancePlanFileName;
  final DateTime? maintenancePlanUpdatedAt;
  final int? maintenancePlanSizeBytes;
  final double? odometerKm;
  final double? nextServiceKm;
  final DateTime? nextServiceDate;
  final DateTime? lastServiceDate;
  final String? lastServiceNotes;

  bool get hasMaintenancePlan =>
      maintenancePlanFileName != null && maintenancePlanFileName!.isNotEmpty && (maintenancePlanSizeBytes ?? 0) > 0;

  bool get hasStructuredMaintenance =>
      odometerKm != null || nextServiceKm != null || nextServiceDate != null || lastServiceDate != null;

  double? get kmUntilNextService {
    if (odometerKm == null || nextServiceKm == null) return null;
    return nextServiceKm! - odometerKm!;
  }

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
    String? maintenancePlanFileName,
    DateTime? maintenancePlanUpdatedAt,
    int? maintenancePlanSizeBytes,
    double? odometerKm,
    double? nextServiceKm,
    DateTime? nextServiceDate,
    DateTime? lastServiceDate,
    String? lastServiceNotes,
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
      maintenancePlanFileName: maintenancePlanFileName ?? this.maintenancePlanFileName,
      maintenancePlanUpdatedAt: maintenancePlanUpdatedAt ?? this.maintenancePlanUpdatedAt,
      maintenancePlanSizeBytes: maintenancePlanSizeBytes ?? this.maintenancePlanSizeBytes,
      odometerKm: odometerKm ?? this.odometerKm,
      nextServiceKm: nextServiceKm ?? this.nextServiceKm,
      nextServiceDate: nextServiceDate ?? this.nextServiceDate,
      lastServiceDate: lastServiceDate ?? this.lastServiceDate,
      lastServiceNotes: lastServiceNotes ?? this.lastServiceNotes,
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
    this.distanceKm,
  });

  final String id;
  final String vehicleId;
  final String vehicleName;
  final String driverId;
  final String driverName;
  final MovementAction action;
  final DateTime createdAt;
  final String? location;
  final double? distanceKm;
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

enum AnnouncementResponseStatus { completed, rejected }

class FleetAnnouncement {
  const FleetAnnouncement({
    required this.id,
    required this.message,
    required this.createdAt,
    required this.createdByName,
    this.createdById,
    this.active = true,
    this.expiresAt,
    this.targetDriverId,
    this.targetDriverName,
    this.responseStatus,
    this.respondedAt,
    this.respondedByName,
    this.rejectionReason,
  });

  final String id;
  final String message;
  final DateTime createdAt;
  final String createdByName;
  final String? createdById;
  final bool active;
  final DateTime? expiresAt;
  final String? targetDriverId;
  final String? targetDriverName;
  final AnnouncementResponseStatus? responseStatus;
  final DateTime? respondedAt;
  final String? respondedByName;
  final String? rejectionReason;

  bool get isExpired => expiresAt != null && !expiresAt!.isAfter(DateTime.now());

  bool get isGroupTask => targetDriverId == null;

  bool get requiresResponse => true;

  bool get isPendingResponse => active && responseStatus == null && !isExpired;

  bool isVisibleTo(AppUser user) {
    if (isExpired) return false;
    if (message.trim().isEmpty) return false;
    if (user.role == UserRole.admin) return active;
    if (!active) return false;
    if (!isPendingResponse) return false;
    if (isGroupTask) return true;
    return targetDriverId == user.id;
  }
}

class FleetAdminAlert {
  const FleetAdminAlert({
    required this.id,
    required this.announcementId,
    required this.driverId,
    required this.driverName,
    required this.message,
    required this.responseStatus,
    required this.createdAt,
    this.rejectionReason,
    this.viewed = false,
    this.viewedAt,
    this.isGroupTask = false,
  });

  final String id;
  final String announcementId;
  final String driverId;
  final String driverName;
  final String message;
  final AnnouncementResponseStatus responseStatus;
  final String? rejectionReason;
  final DateTime createdAt;
  final bool viewed;
  final DateTime? viewedAt;
  final bool isGroupTask;

  bool get isRejected => responseStatus == AnnouncementResponseStatus.rejected;
}

class DriverIssueReport {
  const DriverIssueReport({
    required this.id,
    required this.driverId,
    required this.driverName,
    required this.message,
    required this.createdAt,
    this.vehicleId,
    this.vehicleName,
  });

  final String id;
  final String driverId;
  final String driverName;
  final String message;
  final DateTime createdAt;
  final String? vehicleId;
  final String? vehicleName;
}

enum MaintenanceAlertKind { kmDue, dateDue }

class MaintenanceAlert {
  const MaintenanceAlert({
    required this.vehicleId,
    required this.vehicleName,
    required this.kind,
    required this.message,
  });

  final String vehicleId;
  final String vehicleName;
  final MaintenanceAlertKind kind;
  final String message;
}

class MaintenanceLog {
  const MaintenanceLog({
    required this.id,
    required this.vehicleId,
    required this.serviceDate,
    required this.odometerKm,
    required this.serviceType,
    required this.createdByName,
    required this.createdAt,
    this.notes,
    this.cost,
  });

  final String id;
  final String vehicleId;
  final DateTime serviceDate;
  final double odometerKm;
  final String serviceType;
  final String? notes;
  final double? cost;
  final String createdByName;
  final DateTime createdAt;
}

class VehicleChecklistItemDef {
  const VehicleChecklistItemDef({required this.id, required this.label});

  final String id;
  final String label;
}

abstract final class VehicleChecklistConfig {
  static const items = <VehicleChecklistItemDef>[
    VehicleChecklistItemDef(id: 'documentacao', label: 'Documentacao do veiculo (CRLV)'),
    VehicleChecklistItemDef(id: 'pneus', label: 'Pneus (calibragem e desgaste)'),
    VehicleChecklistItemDef(id: 'freios', label: 'Freios e pedal'),
    VehicleChecklistItemDef(id: 'luzes', label: 'Luzes, setas e farois'),
    VehicleChecklistItemDef(id: 'oleo', label: 'Nivel de oleo do motor'),
    VehicleChecklistItemDef(id: 'agua', label: 'Agua do radiador'),
    VehicleChecklistItemDef(id: 'espelhos', label: 'Espelhos retrovisores'),
    VehicleChecklistItemDef(id: 'limpador', label: 'Limpador de para-brisa'),
    VehicleChecklistItemDef(id: 'combustivel', label: 'Combustivel suficiente'),
    VehicleChecklistItemDef(id: 'extintor', label: 'Extintor e triangulo'),
    VehicleChecklistItemDef(id: 'carroceria', label: 'Carroceria sem avarias aparentes'),
  ];
}

class VehicleChecklist {
  const VehicleChecklist({
    required this.id,
    required this.driverId,
    required this.driverName,
    required this.vehicleId,
    required this.vehicleName,
    required this.vehiclePlate,
    required this.vehicleModel,
    required this.checklistDate,
    required this.items,
    required this.completedAt,
    this.notes,
    this.photoUrls = const [],
    this.signatureBase64,
  });

  final String id;
  final String driverId;
  final String driverName;
  final String vehicleId;
  final String vehicleName;
  final String vehiclePlate;
  final String vehicleModel;
  final String checklistDate;
  final Map<String, bool> items;
  final DateTime completedAt;
  final String? notes;
  final List<String> photoUrls;
  final String? signatureBase64;

  int get missingItemsCount =>
      VehicleChecklistConfig.items.where((item) => items[item.id] != true).length;
  bool get hasPhotos => photoUrls.isNotEmpty;
  bool get hasSignature => signatureBase64 != null && signatureBase64!.isNotEmpty;
}

String checklistDateKey([DateTime? date]) {
  final value = date ?? DateTime.now();
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String vehicleChecklistDocId({
  required String driverId,
  required String vehicleId,
  DateTime? date,
}) =>
    '${driverId}_${vehicleId}_${checklistDateKey(date)}';