import '../models/app_models.dart';
import 'location_tracking_service.dart';

abstract final class DriverTrackFilter {
  static List<DriverTrack> activeOnly(List<DriverTrack> tracks, List<Vehicle> vehicles) {
    return forMapDisplay(tracks, vehicles);
  }

  static List<DriverTrack> forMapDisplay(List<DriverTrack> tracks, List<Vehicle> vehicles) {
    final movingByDriver = _movingByDriver(vehicles);
    final now = DateTime.now();

    return tracks
        .where((track) {
          final vehicle = movingByDriver[track.driverId];
          if (vehicle == null || vehicle.id != track.vehicleId) return false;
          final age = now.difference(track.updatedAt);
          if (age <= LocationTrackingConfig.displayMaxAge) return true;
          if (age <= LocationTrackingConfig.displayStaleMaxAge) return true;
          return age <= const Duration(hours: 6);
        })
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  static bool isStale(DriverTrack track) {
    return DateTime.now().difference(track.updatedAt) > LocationTrackingConfig.displayMaxAge;
  }

  static List<String> orphanDriverIds(List<DriverTrack> tracks, List<Vehicle> vehicles) {
    final movingByDriver = _movingByDriver(vehicles);

    return tracks
        .map((track) => track.driverId)
        .where((driverId) {
          final track = tracks.firstWhere((item) => item.driverId == driverId);
          final vehicle = movingByDriver[driverId];
          return vehicle == null || vehicle.id != track.vehicleId;
        })
        .toSet()
        .toList();
  }

  static Map<String, Vehicle> _movingByDriver(List<Vehicle> vehicles) {
    final movingByDriver = <String, Vehicle>{};
    for (final vehicle in vehicles) {
      if (vehicle.status == VehicleStatus.moving && vehicle.currentDriverId != null) {
        movingByDriver[vehicle.currentDriverId!] = vehicle;
      }
    }
    return movingByDriver;
  }
}
