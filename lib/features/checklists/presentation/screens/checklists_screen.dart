import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/corporate_ui.dart';
import '../../../../core/widgets/main_app_shell.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/app_providers.dart';
import '../widgets/checklist_detail_sheet.dart';
import 'checklist_pdf_viewer_screen.dart';

class ChecklistsScreen extends ConsumerWidget {
  const ChecklistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final isAdmin = user?.role == UserRole.admin;
    final checklistsAsync = ref.watch(vehicleChecklistsProvider);

    return Scaffold(
      appBar: CorporateAppBar(
        title: isAdmin ? 'Checklists da frota' : 'Meus checklists',
        showBack: false,
      ),
      body: checklistsAsync.when(
        loading: () => const CorporateEmptyState(
          icon: Icons.checklist_rtl,
          message: 'Nenhum checklist registrado ainda.',
        ),
        error: (error, _) => Center(child: Text('Erro ao carregar checklists: $error')),
        data: (checklists) {
          if (checklists.isEmpty) {
            return CorporateEmptyState(
              icon: Icons.checklist_rtl,
              message: isAdmin
                  ? 'Nenhum checklist registrado ainda.\n\nQuando um motorista concluir a inspecao, aparecera aqui.'
                  : 'Voce ainda nao concluiu nenhum checklist.\n\nAo iniciar um veiculo pela primeira vez no dia, o checklist sera solicitado.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            itemCount: checklists.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) => _ChecklistTile(
              checklist: checklists[index],
              showDriverName: isAdmin,
            ),
          );
        },
      ),
    );
  }
}

class _ChecklistTile extends StatelessWidget {
  const _ChecklistTile({
    required this.checklist,
    required this.showDriverName,
  });

  final VehicleChecklist checklist;
  final bool showDriverName;

  @override
  Widget build(BuildContext context) {
    return CorporateSurface(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openChecklistDetailSheet(context, checklist),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                        if (showDriverName)
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
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => openChecklistDetailSheet(context, checklist),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('Detalhes'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => openChecklistPdfViewer(context, checklist),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('Ver PDF'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
