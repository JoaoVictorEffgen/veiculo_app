import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class ResolvedAddress {
  const ResolvedAddress({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;

  LatLng get latLng => LatLng(latitude, longitude);
}

class NavigationRoutePlan {
  const NavigationRoutePlan({
    required this.destinationLabel,
    required this.points,
    required this.totalDistanceMeters,
  });

  final String destinationLabel;
  final List<LatLng> points;
  final double totalDistanceMeters;

  double get totalDistanceKm => totalDistanceMeters / 1000;

  double remainingDistanceMeters(LatLng current) {
    if (points.isEmpty) return 0;
    if (points.length == 1) {
      return Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        points.first.latitude,
        points.first.longitude,
      );
    }

    var closestIndex = 0;
    var closestDistance = double.infinity;
    for (var index = 0; index < points.length; index++) {
      final distance = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        points[index].latitude,
        points[index].longitude,
      );
      if (distance < closestDistance) {
        closestDistance = distance;
        closestIndex = index;
      }
    }

    var remaining = 0.0;
    for (var index = closestIndex; index < points.length - 1; index++) {
      remaining += Geolocator.distanceBetween(
        points[index].latitude,
        points[index].longitude,
        points[index + 1].latitude,
        points[index + 1].longitude,
      );
    }
    return remaining;
  }
}

String formatRouteDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}
