import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/fleet_period_filter.dart';
import '../../../../core/widgets/admin_only_gate.dart';
import '../../../../core/widgets/corporate_ui.dart';
import '../../../../core/widgets/main_app_shell.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/app_providers.dart';

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  var _markedViewed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markAlertsViewed());
  }

  Future<void> _markAlertsViewed() async {
    if (_markedViewed) return;
    final admin = ref.read(authControllerProvider).user;
    if (admin?.role != UserRole.admin) return;
    _markedViewed = true;
    await ref.read(repositoryProvider).markAdminAlertsViewed(admin!);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(adminAlertsProvider, (_, __) {
      if (!_markedViewed) _markAlertsViewed();
    });

    final vehicles = ref.watch(vehicleControllerProvider);
    final period = ref.watch(alertsPeriodProvider);
    final periodRange = period.resolveRange();
    final allAdminAlerts = ref.watch(adminAlertsProvider).valueOrNull ?? const <FleetAdminAlert>[];
    final allDriverReports = ref.watch(driverIssueReportsProvider).valueOrNull ?? const <DriverIssueReport>[];
    final maintenanceAlerts = ref.watch(maintenanceAlertsProvider);
    final now = DateTime.now();

    final adminAlerts = allAdminAlerts
        .where((alert) => isDateInFleetPeriod(alert.createdAt, period, now: now))
        .toList();
    final driverReports = allDriverReports
        .where((report) => isDateInFleetPeriod(report.createdAt, period, now: now))
        .toList();

    final idleVehicles = vehicles.where((vehicle) {
      if (vehicle.status != VehicleStatus.stopped || vehicle.stoppedAt == null) return false;
      if (!isDateInFleetPeriod(vehicle.stoppedAt!, period, now: now)) return false;
      return now.difference(vehicle.stoppedAt!).inHours >= 24;
    }).toList();

    final hasAlerts = idleVehicles.isNotEmpty || adminAlerts.isNotEmpty || driverReports.isNotEmpty || maintenanceAlerts.isNotEmpty;

    return AdminOnlyGate(
      child: Scaffold(
        appBar: const CorporateAppBar(title: 'Alertas da frota'),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            CorporatePageHeader(
              title: 'Alertas administrativos',
              subtitle: hasAlerts
                  ? 'Relatos de motoristas, respostas de tarefas e veiculos parados.'
                  : 'Nenhum alerta ativo no periodo selecionado.',
            ),
            const SizedBox(height: 16),
            FleetPeriodFilter(
              period: period,
              onChanged: (value) => ref.read(alertsPeriodProvider.notifier).state = value,
            ),
            const SizedBox(height: 16),
            if (!hasAlerts)
              CorporateEmptyState(
                icon: Icons.check_circle_outline,
                message: 'Nenhum alerta entre ${formatDateTime(periodRange.start)} e ${formatDateTime(periodRange.end)}.',
              ),
            if (maintenanceAlerts.isNotEmpty) ...[
              const CorporateSectionTitle(title: 'Manutencao dos veiculos'),
              ...maintenanceAlerts.map((alert) => _MaintenanceAlertTile(alert: alert)),
              const SizedBox(height: 16),
            ],
            if (driverReports.isNotEmpty) ...[
              const CorporateSectionTitle(title: 'Relatos de problemas'),
              ...driverReports.map((report) => _DriverReportCard(report: report)),
              const SizedBox(height: 16),
            ],
            if (adminAlerts.isNotEmpty) ...[
              const CorporateSectionTitle(title: 'Respostas de tarefas'),
              ...adminAlerts.map((alert) => _AdminAlertCard(alert: alert)),
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

class _DriverReportCard extends ConsumerWidget {
  const _DriverReportCard({required this.report});

  final DriverIssueReport report;

  Future<void> _reply(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final admin = ref.read(authControllerProvider).user;
    if (admin == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Responder ${report.driverName}'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Sua resposta',
            hintText: 'Orientacao, autorizacao ou proximos passos...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enviar resposta')),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      controller.dispose();
      return;
    }

    final error = await ref.read(repositoryProvider).replyToDriverIssueReport(
          admin,
          report.id,
          controller.text,
        );
    controller.dispose();

    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Resposta enviada para ${report.driverName}.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CorporateSurface(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.statusStopped.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.report, color: AppColors.statusStopped),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${report.driverName}${report.vehicleName == null ? '' : ' • ${report.vehicleName}'}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(report.message, style: const TextStyle(fontSize: 14, height: 1.35)),
                    const SizedBox(height: 6),
                    Text(
                      formatDateTime(report.createdAt),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (report.hasAdminReply) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.statusMovingBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.statusMoving.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Resposta • ${report.repliedByName ?? 'Administracao'}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(report.adminReply!, style: const TextStyle(fontSize: 13, height: 1.35)),
                  if (report.repliedAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      formatDateTime(report.repliedAt!),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (!report.hasAdminReply) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _reply(context, ref),
                icon: const Icon(Icons.reply_outlined, size: 18),
                label: const Text('Responder motorista'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdminAlertCard extends StatelessWidget {
  const _AdminAlertCard({required this.alert});

  final FleetAdminAlert alert;

  @override
  Widget build(BuildContext context) {
    final isCompleted = alert.responseStatus == AnnouncementResponseStatus.completed;
    final icon = isCompleted ? Icons.check_circle : Icons.cancel;
    final iconColor = isCompleted ? AppColors.statusMoving : AppColors.statusStopped;
    final statusLabel = isCompleted ? 'Concluido' : 'Recusado';

    return CorporateSurface(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: (isCompleted ? AppColors.statusMovingBg : AppColors.statusStopped.withValues(alpha: 0.12)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor),
              ),
              if (!alert.viewed)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppColors.statusStopped,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.isGroupTask
                      ? 'Tarefa geral concluida • ${alert.driverName}'
                      : '$statusLabel • ${alert.driverName}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(alert.message, style: const TextStyle(fontSize: 14, height: 1.35)),
                if (alert.isRejected && alert.rejectionReason != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Justificativa',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(alert.rejectionReason!, style: const TextStyle(fontSize: 13, height: 1.35)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  formatDateTime(alert.createdAt),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MaintenanceAlertTile extends StatelessWidget {
  const _MaintenanceAlertTile({required this.alert});

  final MaintenanceAlert alert;

  @override
  Widget build(BuildContext context) {
    return CorporateSurface(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          alert.kind == MaintenanceAlertKind.kmDue ? Icons.speed_outlined : Icons.event_busy_outlined,
          color: AppColors.statusStopped,
        ),
        title: Text(alert.vehicleName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(alert.message),
      ),
    );
  }
}
