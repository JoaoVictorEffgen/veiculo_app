import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/admin_only_gate.dart';
import '../../../../core/widgets/corporate_ui.dart';
import '../../../../core/widgets/main_app_shell.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/app_providers.dart';
import '../../../../shared/services/vehicle_checklist_pdf_service.dart';

class ChecklistHistoryScreen extends ConsumerWidget {
  const ChecklistHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checklistsAsync = ref.watch(vehicleChecklistsProvider);

    return AdminOnlyGate(
      child: Scaffold(
        appBar: const CorporateAppBar(title: 'Historico de checklists', showBack: true),
        body: checklistsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Erro ao carregar checklists: $error')),
          data: (checklists) {
            if (checklists.isEmpty) {
              return const CorporateEmptyState(
                icon: Icons.checklist_rtl,
                message: 'Nenhum checklist registrado ainda.\n\n'
                    'Quando um motorista concluir a inspecao antes de iniciar, aparecera aqui.',
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              itemCount: checklists.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _ChecklistHistoryTile(checklist: checklists[index]),
            );
          },
        ),
      ),
    );
  }
}

class _ChecklistHistoryTile extends StatelessWidget {
  const _ChecklistHistoryTile({required this.checklist});

  final VehicleChecklist checklist;

  @override
  Widget build(BuildContext context) {
    return CorporateSurface(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(context, checklist),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.statusMovingBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.checklist_rtl, color: AppColors.statusMoving),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${checklist.vehicleName} • ${checklist.vehiclePlate}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Motorista: ${checklist.driverName}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    Text(
                      '${checklist.checklistDate} • ${formatDateTime(checklist.completedAt)}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    if (checklist.missingItemsCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${checklist.missingItemsCount} item(ns) com possivel falta',
                          style: const TextStyle(color: AppColors.statusStopped, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
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

  Future<void> _openDetail(BuildContext context, VehicleChecklist checklist) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => _ChecklistDetailSheet(
          checklist: checklist,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

class _ChecklistDetailSheet extends StatelessWidget {
  const _ChecklistDetailSheet({
    required this.checklist,
    required this.scrollController,
  });

  final VehicleChecklist checklist;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final pdfService = VehicleChecklistPdfService();

    return Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(99)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    checklist.vehicleName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text(
                  '${checklist.vehicleModel} • ${checklist.vehiclePlate}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 4),
                Text('Motorista: ${checklist.driverName}'),
                Text('Data: ${checklist.checklistDate} • ${formatDateTime(checklist.completedAt)}'),
                const SizedBox(height: 16),
                const CorporateSectionTitle(title: 'Itens verificados'),
                ...VehicleChecklistConfig.items.map(
                  (item) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      checklist.items[item.id] == true ? Icons.check_circle : Icons.cancel,
                      color: checklist.items[item.id] == true ? AppColors.statusMoving : AppColors.statusStopped,
                      size: 20,
                    ),
                    title: Text(item.label, style: const TextStyle(fontSize: 14)),
                    subtitle: checklist.items[item.id] != true
                        ? const Text('FALTA / PROBLEMA', style: TextStyle(color: AppColors.statusStopped, fontSize: 11))
                        : const Text('OK', style: TextStyle(color: AppColors.statusMoving, fontSize: 11)),
                  ),
                ),
                if (checklist.hasSignature) ...[
                  const SizedBox(height: 12),
                  const CorporateSectionTitle(title: 'Assinatura'),
                  const Text('Assinatura digital registrada no documento PDF.', style: TextStyle(fontSize: 13)),
                ],
                if (checklist.notes != null && checklist.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const CorporateSectionTitle(title: 'Observacoes'),
                  Text(checklist.notes!, style: const TextStyle(fontSize: 14, height: 1.35)),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => pdfService.share(checklist),
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Compartilhar PDF'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final file = await pdfService.download(checklist);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('PDF salvo em: ${file.path}')),
                            );
                          }
                        },
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Baixar PDF'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
