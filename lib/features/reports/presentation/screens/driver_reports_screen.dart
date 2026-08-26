import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/iterable_extensions.dart';
import '../../../../core/widgets/corporate_ui.dart';
import '../../../../core/widgets/main_app_shell.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/app_providers.dart';

class DriverReportsScreen extends ConsumerStatefulWidget {
  const DriverReportsScreen({super.key});

  @override
  ConsumerState<DriverReportsScreen> createState() => _DriverReportsScreenState();
}

class _DriverReportsScreenState extends ConsumerState<DriverReportsScreen> {
  final _messageController = TextEditingController();
  String? _selectedVehicleId;
  var _markedRepliesViewed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRepliesViewed());
  }

  Future<void> _markRepliesViewed() async {
    if (_markedRepliesViewed) return;
    final user = ref.read(authControllerProvider).user;
    if (user == null || user.role != UserRole.driver) return;
    _markedRepliesViewed = true;
    await ref.read(repositoryProvider).markDriverReportRepliesViewed(user);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit(AppUser driver) async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Descreva o problema antes de enviar.')),
      );
      return;
    }

    final vehicles = ref.read(vehicleControllerProvider);
    final vehicle = _selectedVehicleId == null
        ? null
        : vehicles.where((item) => item.id == _selectedVehicleId).firstOrNull;

    final error = await ref.read(repositoryProvider).submitDriverIssueReport(
          driver,
          message: message,
          vehicleId: vehicle?.id,
          vehicleName: vehicle?.name,
        );

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    _messageController.clear();
    setState(() => _selectedVehicleId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Relato enviado para o administrador.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    if (user == null || user.role != UserRole.driver) {
      return const Scaffold(
        body: Center(child: Text('Acesso disponivel apenas para motoristas.')),
      );
    }

    final reportsAsync = ref.watch(driverIssueReportsProvider);
    final vehicles = ref.watch(vehicleControllerProvider);

    ref.listen(driverIssueReportsProvider, (_, __) {
      if (!_markedRepliesViewed) _markRepliesViewed();
    });

    return Scaffold(
      appBar: const CorporateAppBar(title: 'Relatar problema'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          const CorporatePageHeader(
            title: 'Problemas no veiculo',
            subtitle: 'Avise a administracao sobre pane, avaria ou situacao na estrada.',
          ),
          const SizedBox(height: 16),
          CorporateSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: _selectedVehicleId,
                  decoration: const InputDecoration(
                    labelText: 'Veiculo (opcional)',
                    prefixIcon: Icon(Icons.local_shipping_outlined),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Nao informado')),
                    ...vehicles.map(
                      (vehicle) => DropdownMenuItem<String?>(
                        value: vehicle.id,
                        child: Text('${vehicle.name} • ${vehicle.plate}'),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _selectedVehicleId = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _messageController,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Descreva o problema',
                    hintText: 'Ex.: pneu furado na estrada, motor falhando, acidente leve...',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _submit(user),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('ENVIAR RELATO'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const CorporateSectionTitle(title: 'Meus relatos'),
          const SizedBox(height: 8),
          reportsAsync.when(
            loading: () => const CorporateEmptyState(
              icon: Icons.report_outlined,
              message: 'Voce ainda nao enviou nenhum relato.',
            ),
            error: (error, _) => CorporateEmptyState(
              icon: Icons.cloud_off_outlined,
              message: error.toString().contains('index')
                  ? 'Sincronizando relatos. Aguarde alguns segundos e recarregue a pagina.'
                  : 'Erro ao carregar relatos. Tente novamente em instantes.',
            ),
            data: (reports) {
              if (reports.isEmpty) {
                return const CorporateEmptyState(
                  icon: Icons.report_outlined,
                  message: 'Voce ainda nao enviou nenhum relato.',
                );
              }

              return Column(
                children: reports
                    .map(
                      (report) => CorporateSurface(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (report.hasUnreadAdminReply) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.notifications_active_outlined, color: AppColors.accent, size: 16),
                                    SizedBox(width: 6),
                                    Text(
                                      'Nova resposta da administracao',
                                      style: TextStyle(
                                        color: AppColors.accent,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: AppColors.statusStopped, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    report.vehicleName ?? 'Veiculo nao informado',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Text(
                                  formatDateTime(report.createdAt),
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(report.message, style: const TextStyle(height: 1.35)),
                            if (report.hasAdminReply) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
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
                                      'Resposta da administracao • ${report.repliedByName ?? 'Admin'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
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
                          ],
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
