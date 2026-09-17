import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme.dart';
import '../../shared/models/navigation_route.dart';
import '../../shared/services/app_providers.dart';

Future<void> openNavigationRouteScreen(
  BuildContext context, {
  required NavigationRoutePlan route,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => NavigationRouteScreen(route: route),
    ),
  );
}

class NavigationRouteScreen extends ConsumerStatefulWidget {
  const NavigationRouteScreen({super.key, required this.route});

  final NavigationRoutePlan route;

  @override
  ConsumerState<NavigationRouteScreen> createState() => _NavigationRouteScreenState();
}

class _NavigationRouteScreenState extends ConsumerState<NavigationRouteScreen> {
  final _mapController = MapController();
  StreamSubscription<Position>? _positionSubscription;
  LatLng? _myPosition;
  double? _remainingMeters;
  String? _locationError;

  @override
  void initState() {
    super.initState();
    _remainingMeters = widget.route.totalDistanceMeters;
    unawaited(_startTracking());
  }

  Future<void> _startTracking() async {
    final service = ref.read(locationTrackingServiceProvider);
    final allowed = await service.ensurePermission(requireBackground: false);
    if (!mounted) return;
    if (!allowed) {
      setState(() => _locationError = service.permissionIssue ?? 'Permissao de localizacao negada.');
      return;
    }

    await _refreshPosition();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
      ),
    ).listen((position) {
      if (!mounted) return;
      _applyPosition(LatLng(position.latitude, position.longitude));
    });
  }

  Future<void> _refreshPosition() async {
    final snapshot = await ref.read(locationTrackingServiceProvider).getCurrentCoordinates();
    if (!mounted || snapshot == null) return;
    _applyPosition(LatLng(snapshot.latitude, snapshot.longitude));
  }

  void _applyPosition(LatLng position) {
    final remaining = widget.route.remainingDistanceMeters(position);
    setState(() {
      _myPosition = position;
      _remainingMeters = remaining;
      _locationError = null;
    });
    _mapController.move(position, _mapController.camera.zoom);
  }

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
    super.dispose();
  }

  LatLng get _destination => widget.route.points.last;

  @override
  Widget build(BuildContext context) {
    final remainingLabel = _remainingMeters == null ? '--' : formatRouteDistance(_remainingMeters!);
    final totalLabel = formatRouteDistance(widget.route.totalDistanceMeters);
    final mapCenter = _myPosition ?? widget.route.points.first;

    return Scaffold(
      appBar: AppBar(
        title: Text('Rota — ${widget.route.destinationLabel}'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Restante: $remainingLabel',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total da rota: $totalLabel',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                if (_locationError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _locationError!,
                    style: const TextStyle(color: AppColors.statusStopped, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: mapCenter,
                    initialZoom: 13,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.vehicle_control_app',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: widget.route.points,
                          strokeWidth: 5,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        if (_myPosition != null)
                          Marker(
                            point: _myPosition!,
                            width: 36,
                            height: 36,
                            child: const Icon(Icons.person_pin_circle, color: AppColors.accent, size: 36),
                          ),
                        Marker(
                          point: _destination,
                          width: 36,
                          height: 36,
                          child: const Icon(Icons.place, color: AppColors.statusMoving, size: 36),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
