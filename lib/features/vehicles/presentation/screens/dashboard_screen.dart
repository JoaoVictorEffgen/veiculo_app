import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/app_providers.dart';

/// Dashboard principal com os veículos — implementação completa na Etapa 4
/// (cards por veículo, separação EM MOVIMENTO / PARADO).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    final vehicles = ref.watch(vehicleControllerProvider);
    final moving = vehicles.where((vehicle) => vehicle.status == VehicleStatus.moving).toList();
    final stopped = vehicles.where((vehicle) => vehicle.status == VehicleStatus.stopped).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(user?.role == UserRole.admin ? 'Área administrativa' : 'Veículos'),
        actions: [
          if (user?.role == UserRole.admin)
            IconButton(onPressed: () => context.push(AppRoutes.admin), icon: const Icon(Icons.admin_panel_settings_outlined), tooltip: 'Administração'),
          IconButton(onPressed: () => context.push(AppRoutes.history), icon: const Icon(Icons.history), tooltip: 'Histórico'),
          IconButton(onPressed: () { ref.read(authControllerProvider.notifier).logout(); context.go(AppRoutes.login); }, icon: const Icon(Icons.logout), tooltip: 'Sair'),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.read(vehicleControllerProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
          children: [
            Text('Olá, ${user?.name ?? 'motorista'}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${moving.length} em movimento • ${stopped.length} parados', style: const TextStyle(color: AppColors.textSecondary)),
            if (user?.role == UserRole.admin) ...[
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: () => context.push(AppRoutes.admin), icon: const Icon(Icons.admin_panel_settings_outlined), label: const Text('ABRIR PAINEL ADMINISTRATIVO')),
            ],
            const SizedBox(height: 20),
            _SectionTitle(title: 'EM MOVIMENTO', count: moving.length, color: AppColors.statusMoving),
            ...moving.map((vehicle) => _VehicleCard(vehicle: vehicle, user: user, ref: ref)),
            const SizedBox(height: 12),
            _SectionTitle(title: 'PARADOS / DISPONÍVEIS', count: stopped.length, color: AppColors.statusStopped),
            ...stopped.map((vehicle) => _VehicleCard(vehicle: vehicle, user: user, ref: ref)),
          ],
        ),
      ),
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
        child: Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 8), Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)), const Spacer(), Text('$count')]),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(vehicle.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))), Text(vehicle.plate, style: const TextStyle(color: AppColors.textSecondary))]),
          const SizedBox(height: 4),
          Text(vehicle.model, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          Row(children: [Icon(isMoving ? Icons.circle : Icons.circle_outlined, color: color, size: 16), const SizedBox(width: 8), Text(isMoving ? 'EM MOVIMENTO' : 'PARADO', style: TextStyle(color: color, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 8),
          Text('Motorista: ${vehicle.currentDriverName ?? 'Nenhum'}'),
          if (isMoving) Text('Desde: ${formatDateTime(vehicle.startedAt)}') else Text('Local: ${vehicle.stoppedLocation ?? 'Não informado'}'),
          const SizedBox(height: 14),
          if (isMoving && vehicle.currentDriverId == user?.id)
            OutlinedButton.icon(onPressed: () => _stop(context), icon: const Icon(Icons.stop_circle_outlined), label: const Text('PARAR / OFF'))
          else if (!isMoving)
            ElevatedButton.icon(onPressed: () => _start(context), icon: const Icon(Icons.play_circle_outline), label: const Text('INICIAR / ON'))
          else
            const Text('Veículo indisponível para outro motorista.', style: TextStyle(color: AppColors.textSecondary)),
        ]),
      ),
    );
  }

  void _start(BuildContext context) {
    final error = ref.read(vehicleControllerProvider.notifier).start(vehicle.id, user!);
    if (error != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _stop(BuildContext context) async {
    final controller = TextEditingController();
    final location = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: const Text('Veículo parado'), content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Local onde foi deixado')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), ElevatedButton(onPressed: () { if (controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text); }, child: const Text('Confirmar parada'))]));
    controller.dispose();
    if (location == null || !context.mounted) return;
    final error = ref.read(vehicleControllerProvider.notifier).stop(vehicle.id, user!, location);
    if (error != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}
