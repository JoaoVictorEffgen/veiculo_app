import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/admin_only_gate.dart';
import '../../../../core/widgets/corporate_ui.dart';
import '../../../../core/widgets/main_app_shell.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/app_providers.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicles = ref.watch(vehicleControllerProvider);
    final announcements = ref.watch(fleetAnnouncementsProvider).valueOrNull ?? const <FleetAnnouncement>[];
    final now = DateTime.now();

    final idleVehicles = vehicles.where((vehicle) {
      if (vehicle.status != VehicleStatus.stopped || vehicle.stoppedAt == null) return false;
      return now.difference(vehicle.stoppedAt!).inHours >= 24;
    }).toList();

    final pendingResponses = announcements.where((item) => item.isPendingResponse).toList();
    final hasAlerts = idleVehicles.isNotEmpty || pendingResponses.isNotEmpty;

    return AdminOnlyGate(
      child: Scaffold(
        appBar: const CorporateAppBar(title: 'Alertas da frota'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            CorporatePageHeader(
              title: 'Alertas administrativos',
              subtitle: hasAlerts
                  ? 'Itens que precisam de atencao.'
                  : 'Nenhum alerta ativo no momento.',
            ),
            const SizedBox(height: 16),
            if (!hasAlerts)
              const CorporateEmptyState(
                icon: Icons.check_circle_outline,
                message: 'Nenhum alerta relevante no momento.',
              ),
            if (pendingResponses.isNotEmpty) ...[
              const CorporateSectionTitle(title: 'Lembretes aguardando resposta'),
              ...pendingResponses.map(
                (announcement) => CorporateSurface(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.pending_actions, color: AppColors.primary),
                    title: Text(announcement.targetDriverName ?? 'Motorista'),
                    subtitle: Text(announcement.message),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (idleVehicles.isNotEmpty) ...[
              const CorporateSectionTitle(title: 'Veiculos parados ha mais de 24h'),
              ...idleVehicles.map(
                (vehicle) => CorporateSurface(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber_rounded, color: AppColors.statusStopped),
                    title: Text(vehicle.name),
                    subtitle: Text(
                      'Parado desde ${formatDateTime(vehicle.stoppedAt)} • ${vehicle.stoppedLocation ?? 'Local nao informado'}',
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
