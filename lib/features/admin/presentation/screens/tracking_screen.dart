import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/admin_only_gate.dart';
import '../../../../core/widgets/corporate_ui.dart';
import '../../../../core/widgets/main_app_shell.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/app_providers.dart';
import '../../../../shared/services/driver_track_filter.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  final _mapController = MapController();
  final _distance = const Distance();
  DateTime? _lastPurgeAt;
  LatLng? _myPosition;
  bool _loadingMyPosition = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_purgeStaleTracks());
      unawaited(_refreshMyPosition());
    });
  }

  Future<void> _refreshMyPosition() async {
    if (_loadingMyPosition) return;
    setState(() => _loadingMyPosition = true);
    final snapshot = await ref.read(locationTrackingServiceProvider).getCurrentCoordinates();
    if (!mounted) return;
    setState(() {
      _loadingMyPosition = false;
      _myPosition = snapshot == null ? null : LatLng(snapshot.latitude, snapshot.longitude);
    });
  }

  Future<void> _purgeStaleTracks() async {
    final now = DateTime.now();
    if (_lastPurgeAt != null && now.difference(_lastPurgeAt!) < const Duration(seconds: 30)) {
      return;
    }

    final tracks = ref.read(rawDriverTracksProvider).valueOrNull;
    if (tracks == null || tracks.isEmpty) return;

    final vehicles = ref.read(vehicleControllerProvider);
    final orphanIds = DriverTrackFilter.orphanDriverIds(tracks, vehicles);
    if (orphanIds.isEmpty) return;

    _lastPurgeAt = now;
    await ref.read(repositoryProvider).purgeOrphanedTracking(orphanIds);
  }

  String? _distanceLabel(Vehicle vehicle) {
    if (_myPosition == null || !vehicle.hasStoppedCoordinates) return null;
    final km = _distance.as(
      LengthUnit.Kilometer,
      _myPosition!,
      LatLng(vehicle.stoppedLatitude!, vehicle.stoppedLongitude!),
    );
    if (km < 1) return '${(km * 1000).round()} m de voce';
    return '${km.toStringAsFixed(1)} km de voce';
  }

  LatLng _resolveMapCenter(List<DriverTrack> tracks, List<Vehicle> parkedVehicles) {
    if (tracks.isNotEmpty) return LatLng(tracks.first.latitude, tracks.first.longitude);
    if (parkedVehicles.isNotEmpty) {
      return LatLng(parkedVehicles.first.stoppedLatitude!, parkedVehicles.first.stoppedLongitude!);
    }
    if (_myPosition != null) return _myPosition!;
    return const LatLng(-23.5505, -46.6333);
  }

  @override
  Widget build(BuildContext context) {
    final tracksAsync = ref.watch(driverTracksProvider);
    final vehicles = ref.watch(vehicleControllerProvider);
    final parkedVehicles = vehicles
        .where((vehicle) => vehicle.status == VehicleStatus.stopped && vehicle.hasStoppedCoordinates)
        .toList()
      ..sort((a, b) => (b.stoppedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.stoppedAt ?? DateTime.fromMillisecondsSinceEpoch(0)));

    ref.listen<AsyncValue<List<DriverTrack>>>(rawDriverTracksProvider, (_, __) {
      unawaited(_purgeStaleTracks());
    });

    ref.listen<AsyncValue<List<DriverTrack>>>(driverTracksProvider, (previous, next) {
      final tracks = next.valueOrNull;
      if (tracks == null || tracks.isEmpty) return;
      final primary = tracks.first;
      _mapController.move(LatLng(primary.latitude, primary.longitude), _mapController.camera.zoom);
    });

    return AdminOnlyGate(
      child: Scaffold(
        appBar: const CorporateAppBar(title: 'Mapa GPS', showFleetRefresh: true),
        body: tracksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Erro ao carregar GPS: $error')),
          data: (tracks) {
            if (tracks.isEmpty && parkedVehicles.isEmpty) {
              return const CorporateEmptyState(
                icon: Icons.map_outlined,
                message: 'Nenhum veiculo no mapa no momento.\n\n'
                    'Veiculos em movimento aparecem ao vivo. '
                    'Apos parar uma corrida, a ultima posicao fica marcada aqui.',
              );
            }

            final staleCount = tracks.where(DriverTrackFilter.isStale).length;
            final center = _resolveMapCenter(tracks, parkedVehicles);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: CorporatePageHeader(
                    title: 'Monitoramento da frota',
                    subtitle: _buildSubtitle(tracks.length, parkedVehicles.length, staleCount),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _loadingMyPosition ? null : _refreshMyPosition,
                      icon: _loadingMyPosition
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location, size: 18),
                      label: const Text('Calcular distancia ate mim'),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: center,
                          initialZoom: 13,
                          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.vehicle_control_app',
                          ),
                          if (_myPosition != null)
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _myPosition!,
                                  width: 36,
                                  height: 36,
                                  child: const Icon(Icons.person_pin_circle, color: AppColors.accent, size: 36),
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: [
                              for (final track in tracks)
                                Marker(
                                  point: LatLng(track.latitude, track.longitude),
                                  width: 120,
                                  height: 80,
                                  alignment: Alignment.topCenter,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
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
                                            DriverTrackFilter.isStale(track)
                                                ? '${track.driverName}\nGPS desatualizado'
                                                : '${track.driverName}\n${track.speedKmh.toStringAsFixed(0)} km/h',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        Icon(
                                          Icons.location_on,
                                          color: DriverTrackFilter.isStale(track)
                                              ? AppColors.statusStopped
                                              : AppColors.statusMoving,
                                          size: 32,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              for (final vehicle in parkedVehicles)
                                Marker(
                                  point: LatLng(vehicle.stoppedLatitude!, vehicle.stoppedLongitude!),
                                  width: 130,
                                  height: 88,
                                  alignment: Alignment.topCenter,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
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
                                            '${vehicle.name}\nParado',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const Icon(Icons.local_parking, color: AppColors.primary, size: 32),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      if (tracks.isNotEmpty) ...[
                        const CorporateSectionTitle(title: 'Em movimento'),
                        const SizedBox(height: 8),
                        ...tracks.map((track) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _TrackTile(track: track),
                            )),
                      ],
                      if (parkedVehicles.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const CorporateSectionTitle(title: 'Ultima localizacao (parados)'),
                        const SizedBox(height: 8),
                        ...parkedVehicles.map(
                          (vehicle) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ParkedVehicleTile(
                              vehicle: vehicle,
                              distanceLabel: _distanceLabel(vehicle),
                              onFocus: () => _mapController.move(
                                LatLng(vehicle.stoppedLatitude!, vehicle.stoppedLongitude!),
                                15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _buildSubtitle(int movingCount, int parkedCount, int staleCount) {
    final parts = <String>[];
    if (movingCount > 0) {
      parts.add(staleCount > 0
          ? '$movingCount em movimento ($staleCount GPS desatualizado)'
          : '$movingCount em movimento');
    }
    if (parkedCount > 0) parts.add('$parkedCount parado(s) com ultima posicao');
    if (_myPosition != null) parts.add('distancia calculada da sua posicao');
    return parts.join(' • ');
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track});

  final DriverTrack track;

  @override
  Widget build(BuildContext context) {
    final stale = DriverTrackFilter.isStale(track);
    return CorporateSurface(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: stale ? AppColors.statusStoppedBg : AppColors.statusMovingBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.directions_car_filled,
              color: stale ? AppColors.statusStopped : AppColors.statusMoving,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.driverName, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${track.vehicleName} • ${formatDateTime(track.updatedAt)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                if (stale)
                  const Text('GPS desatualizado — corrida ainda ativa no sistema', style: TextStyle(color: AppColors.statusStopped, fontSize: 12)),
                Text(
                  '${track.latitude.toStringAsFixed(5)}, ${track.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            stale ? '—' : '${track.speedKmh.toStringAsFixed(0)} km/h',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: stale ? AppColors.statusStopped : AppColors.statusMoving,
            ),
          ),
        ],
      ),
    );
  }
}

class _ParkedVehicleTile extends StatelessWidget {
  const _ParkedVehicleTile({
    required this.vehicle,
    required this.onFocus,
    this.distanceLabel,
  });

  final Vehicle vehicle;
  final VoidCallback onFocus;
  final String? distanceLabel;

  @override
  Widget build(BuildContext context) {
    return CorporateSurface(
      child: InkWell(
        onTap: onFocus,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_parking, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vehicle.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      vehicle.stoppedLocation ?? 'Local nao informado',
                      style: const TextStyle(fontSize: 13, height: 1.3),
                    ),
                    if (vehicle.stoppedAt != null)
                      Text(
                        'Parado em ${formatDateTime(vehicle.stoppedAt!)}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    if (distanceLabel != null)
                      Text(
                        distanceLabel!,
                        style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
