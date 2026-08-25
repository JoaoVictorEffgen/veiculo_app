import '../models/app_models.dart';

class MaintenanceAlertService {
  List<MaintenanceAlert> compute(List<Vehicle> vehicles, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final alerts = <MaintenanceAlert>[];

    for (final vehicle in vehicles) {
      final kmUntil = vehicle.kmUntilNextService;
      if (kmUntil != null && kmUntil <= 500) {
        alerts.add(
          MaintenanceAlert(
            vehicleId: vehicle.id,
            vehicleName: vehicle.name,
            kind: MaintenanceAlertKind.kmDue,
            message: kmUntil <= 0
                ? 'Revisao por km vencida (${vehicle.odometerKm!.toStringAsFixed(0)} km / meta ${vehicle.nextServiceKm!.toStringAsFixed(0)} km)'
                : 'Revisao em ${kmUntil.toStringAsFixed(0)} km (${vehicle.name})',
          ),
        );
      }

      final nextDate = vehicle.nextServiceDate;
      if (nextDate != null) {
        final days = nextDate.difference(DateTime(current.year, current.month, current.day)).inDays;
        if (days <= 7) {
          alerts.add(
            MaintenanceAlert(
              vehicleId: vehicle.id,
              vehicleName: vehicle.name,
              kind: MaintenanceAlertKind.dateDue,
              message: days < 0
                  ? 'Revisao por data vencida em ${nextDate.day.toString().padLeft(2, '0')}/${nextDate.month.toString().padLeft(2, '0')}/${nextDate.year}'
                  : 'Revisao prevista em $days dia(s) (${vehicle.name})',
            ),
          );
        }
      }
    }

    alerts.sort((a, b) => a.vehicleName.compareTo(b.vehicleName));
    return alerts;
  }
}
