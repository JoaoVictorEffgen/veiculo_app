import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme.dart';
import '../utils/date_formatter.dart';
import '../../shared/models/app_models.dart';

class VehicleLocationMapPreview extends StatelessWidget {
  const VehicleLocationMapPreview({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.markerLabel,
    this.subtitle,
    this.isLive = false,
    this.distanceLabel,
    this.height = 180,
  });

  final double latitude;
  final double longitude;
  final String markerLabel;
  final String? subtitle;
  final bool isLive;
  final String? distanceLabel;
  final double height;

  factory VehicleLocationMapPreview.parked({
    required Vehicle vehicle,
    String? distanceLabel,
    double height = 180,
  }) {
    return VehicleLocationMapPreview(
      latitude: vehicle.stoppedLatitude!,
      longitude: vehicle.stoppedLongitude!,
      markerLabel: vehicle.name,
      subtitle: vehicle.stoppedLocation,
      isLive: false,
      distanceLabel: distanceLabel,
      height: height,
    );
  }

  factory VehicleLocationMapPreview.live({
    required DriverTrack track,
    double height = 180,
  }) {
    return VehicleLocationMapPreview(
      latitude: track.latitude,
      longitude: track.longitude,
      markerLabel: track.vehicleName,
      subtitle: '${track.speedKmh.toStringAsFixed(0)} km/h • ${formatDateTime(track.updatedAt)}',
      isLive: true,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: height,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 15,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.vehicle_control_app',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 110,
                      height: 72,
                      alignment: Alignment.topCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                            ),
                            child: Text(
                              markerLabel,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Icon(
                            isLive ? Icons.location_on : Icons.local_parking,
                            color: isLive ? AppColors.statusMoving : AppColors.primary,
                            size: 30,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3)),
        ],
        if (distanceLabel != null) ...[
          const SizedBox(height: 4),
          Text(
            distanceLabel!,
            style: const TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}
