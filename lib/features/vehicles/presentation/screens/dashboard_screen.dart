import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/app_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final vehicles = ref.watch(vehicleControllerProvider);
    final moving = vehicles.where((vehicle) => vehicle.status == VehicleStatus.moving).toList();
    final stopped = vehicles.where((vehicle) => vehicle.status == VehicleStatus.stopped).toList();
    final myVehicle = vehicles
        .where((vehicle) => vehicle.currentDriverId == user?.id && vehicle.status == VehicleStatus.moving)
        .firstOrNull;
    final myTrack = ref.watch(driverTracksProvider).valueOrNull?.where((track) => track.driverId == user?.id).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(user?.role == UserRole.admin ? 'Area administrativa' : 'Veiculos'),
        actions: [
          if (user?.role == UserRole.admin) ...[
            IconButton(onPressed: () => context.push(AppRoutes.fleetDashboard), icon: const Icon(Icons.insights_outlined), tooltip: 'Dashboard da Frota'),
            IconButton(onPressed: () => context.push(AppRoutes.tracking), icon: const Icon(Icons.map_outlined), tooltip: 'Mapa GPS'),
            IconButton(onPressed: () => context.push(AppRoutes.admin), icon: const Icon(Icons.admin_panel_settings_outlined), tooltip: 'Administracao'),
          ],
          IconButton(onPressed: () => context.push(AppRoutes.history), icon: const Icon(Icons.history), tooltip: 'Historico'),
          IconButton(
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go(AppRoutes.login);
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.read(vehicleControllerProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
          children: [
            Text('Ola, ${user?.name ?? 'motorista'}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${moving.length} em movimento • ${stopped.length} parados', style: const TextStyle(color: AppColors.textSecondary)),
            if (myVehicle != null) ...[
              const SizedBox(height: 16),
              Card(
                color: AppColors.statusMovingBg,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_car_filled, color: AppColors.statusMoving),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Voce esta usando', style: TextStyle(color: AppColors.textSecondary)),
                            Text(myVehicle.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            Text('Desde ${formatDateTime(myVehicle.startedAt)}'),
                            if (myTrack != null)
                              Text(
                                'Velocidade: ${myTrack.speedKmh.toStringAsFixed(0)} km/h • GPS ativo',
                                style: const TextStyle(color: AppColors.statusMoving, fontWeight: FontWeight.w600),
                              )
                            else
                              const Text('Aguardando sinal GPS...', style: TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (user?.role == UserRole.admin) ...[
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: () => context.push(AppRoutes.admin), icon: const Icon(Icons.admin_panel_settings_outlined), label: const Text('ABRIR PAINEL ADMINISTRATIVO')),
            ],
            const SizedBox(height: 20),
            _SectionTitle(title: 'EM MOVIMENTO', count: moving.length, color: AppColors.statusMoving),
            if (moving.isEmpty)
              const _EmptySection(message: 'Nenhum veiculo em movimento no momento.')
            else
              ...moving.map((vehicle) => _VehicleCard(vehicle: vehicle, user: user, ref: ref)),
            const SizedBox(height: 12),
            _SectionTitle(title: 'PARADOS / DISPONIVEIS', count: stopped.length, color: AppColors.statusStopped),
            if (stopped.isEmpty)
              const _EmptySection(message: 'Nenhum veiculo parado cadastrado.')
            else
              ...stopped.map((vehicle) => _VehicleCard(vehicle: vehicle, user: user, ref: ref)),
          ],
        ),
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count, required this.color});
  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('$count'),
        ]),
      );
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle, required this.user, required this.ref});
  final Vehicle vehicle;
  final AppUser? user;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final isMoving = vehicle.status == VehicleStatus.moving;
    final color = isMoving ? AppColors.statusMoving : AppColors.statusStopped;
    final isMine = vehicle.currentDriverId == user?.id && isMoving;
    final alreadyUsingAnother = ref.watch(vehicleControllerProvider).any(
          (item) => item.currentDriverId == user?.id && item.status == VehicleStatus.moving && item.id != vehicle.id,
        );

    return Card(
      color: isMine ? AppColors.statusMovingBg : AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(vehicle.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
            Text(vehicle.plate, style: const TextStyle(color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 4),
          Text(vehicle.model, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          Row(children: [
            Icon(isMoving ? Icons.circle : Icons.circle_outlined, color: color, size: 16),
            const SizedBox(width: 8),
            Text(isMoving ? 'EM MOVIMENTO' : 'PARADO', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          Text('Motorista: ${vehicle.currentDriverName ?? 'Nenhum'}'),
          if (isMoving)
            Text('Inicio: ${formatDateTime(vehicle.startedAt)}')
          else ...[
            Text('Local: ${vehicle.stoppedLocation ?? 'Nao informado'}'),
            if (vehicle.stoppedAt != null) Text('Parado desde: ${formatTime(vehicle.stoppedAt)}'),
          ],
          const SizedBox(height: 14),
          if (isMoving && isMine)
            OutlinedButton.icon(onPressed: () => _stop(context), icon: const Icon(Icons.stop_circle_outlined), label: const Text('PARAR / OFF'))
          else if (!isMoving && !alreadyUsingAnother)
            ElevatedButton.icon(onPressed: () => _confirmStart(context), icon: const Icon(Icons.play_circle_outline), label: const Text('INICIAR / ON'))
          else if (!isMoving && alreadyUsingAnother)
            const Text(
              'Voce ja esta usando outro veiculo.',
              style: TextStyle(color: AppColors.textSecondary),
            )
          else if (isMoving)
            const Text(
              'Veiculo indisponivel para outro motorista.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
        ]),
      ),
    );
  }

  Future<void> _confirmStart(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar inicio'),
        content: Text('Deseja iniciar o uso do veiculo ${vehicle.name}?\n\nMotorista: ${user!.name}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('INICIAR / ON')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await ref.read(vehicleControllerProvider.notifier).start(vehicle.id, user!);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _stop(BuildContext context) async {
    final controller = TextEditingController();
    final location = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Veiculo parado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Motorista: ${user!.name}'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Local onde foi deixado'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text.trim());
            },
            child: const Text('CONFIRMAR PARADA'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (location == null || !context.mounted) return;
    final error = await ref.read(vehicleControllerProvider.notifier).stop(vehicle.id, user!, location);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }
}
