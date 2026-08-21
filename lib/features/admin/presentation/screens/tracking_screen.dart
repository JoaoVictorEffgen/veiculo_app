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

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  final _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    final tracksAsync = ref.watch(driverTracksProvider);

    ref.listen<AsyncValue<List<DriverTrack>>>(driverTracksProvider, (previous, next) {
      final tracks = next.valueOrNull;
      if (tracks == null || tracks.isEmpty) return;
      final primary = tracks.first;
      _mapController.move(LatLng(primary.latitude, primary.longitude), _mapController.camera.zoom);
    });

    return AdminOnlyGate(
      child: Scaffold(
        appBar: const CorporateAppBar(title: 'Mapa GPS'),
        body: tracksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Erro ao carregar GPS: $error')),
          data: (tracks) {
            if (tracks.isEmpty) {
              return const CorporateEmptyState(
                icon: Icons.map_outlined,
                message: 'Nenhum motorista em movimento com GPS ativo no momento.\n\n'
                    'O motorista precisa estar com veiculo INICIADO e permitir localizacao no celular.',
              );
            }

            final center = LatLng(tracks.first.latitude, tracks.first.longitude);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: CorporatePageHeader(
                    title: 'Monitoramento em tempo real',
                    subtitle: '${tracks.length} motorista(s) com GPS ativo',
                  ),
                ),
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
                                            '${track.driverName}\n${track.speedKmh.toStringAsFixed(0)} km/h',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const Icon(Icons.location_on, color: AppColors.statusMoving, size: 32),
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
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: tracks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _TrackTile(track: tracks[index]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track});

  final DriverTrack track;

  @override
  Widget build(BuildContext context) {
    return CorporateSurface(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.statusMovingBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.person_pin_circle, color: AppColors.statusMoving),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.driverName, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${track.vehicleName} • ${formatDateTime(track.updatedAt)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                Text(
                  '${track.latitude.toStringAsFixed(5)}, ${track.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '${track.speedKmh.toStringAsFixed(0)} km/h',
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.statusMoving),
          ),
        ],
      ),
    );
  }
}
