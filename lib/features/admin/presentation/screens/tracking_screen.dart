import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/app_providers.dart';

class TrackingScreen extends ConsumerWidget {
  const TrackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    if (user?.role != UserRole.admin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Acesso negado')),
        body: Center(child: ElevatedButton(onPressed: () => context.go(AppRoutes.dashboard), child: const Text('Voltar'))),
      );
    }

    final tracksAsync = ref.watch(driverTracksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa GPS'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: tracksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Erro ao carregar GPS: $error')),
        data: (tracks) {
          if (tracks.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhum motorista em movimento com GPS ativo no momento.\n\n'
                  'O motorista precisa estar com veiculo INICIADO e permitir localizacao no celular.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }

          final center = LatLng(tracks.first.latitude, tracks.first.longitude);

          return Column(
            children: [
              Expanded(
                flex: 3,
                child: FlutterMap(
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
                            height: 70,
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
                                    '${track.driverName}\n${track.speedKmh.toStringAsFixed(0)} km/h',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const Icon(Icons.location_on, color: AppColors.statusMoving, size: 36),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: tracks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => _TrackTile(track: tracks[index]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track});

  final DriverTrack track;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.person_pin_circle, color: AppColors.statusMoving, size: 32),
      title: Text(track.driverName, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text('${track.vehicleName} • ${formatDateTime(track.updatedAt)}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${track.speedKmh.toStringAsFixed(0)} km/h', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.statusMoving)),
          Text(
            '${track.latitude.toStringAsFixed(5)}, ${track.longitude.toStringAsFixed(5)}',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
