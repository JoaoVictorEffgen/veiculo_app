import '../models/app_models.dart';
import 'location_tracking_service.dart';

abstract final class DriverTrackFilter {
  static List<DriverTrack> activeOnly(List<DriverTrack> tracks, List<Vehicle> vehicles) {
    final movingByDriver = <String, Vehicle>{};
    for (final vehicle in vehicles) {
      if (vehicle.status == VehicleStatus.moving && vehicle.currentDriverId != null) {
        movingByDriver[vehicle.currentDriverId!] = vehicle;
      }
    }

    final now = DateTime.now();
    return tracks
        .where((track) {
          final vehicle = movingByDriver[track.driverId];
          if (vehicle == null || vehicle.id != track.vehicleId) return false;
          return now.difference(track.updatedAt) <= LocationTrackingConfig.displayMaxAge;
        })
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  static List<String> orphanDriverIds(List<DriverTrack> tracks, List<Vehicle> vehicles) {
    final activeIds = activeOnly(tracks, vehicles).map((track) => track.driverId).toSet();
    return tracks.map((track) => track.driverId).where((id) => !activeIds.contains(id)).toList();
  }
}
