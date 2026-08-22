import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/corporate_ui.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/vehicle_checklist_pdf_service.dart';
import '../screens/checklist_pdf_viewer_screen.dart';

Future<void> openChecklistDetailSheet(BuildContext context, VehicleChecklist checklist) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => ChecklistDetailSheet(
        checklist: checklist,
        scrollController: scrollController,
      ),
    ),
  );
}

class ChecklistDetailSheet extends StatelessWidget {
  const ChecklistDetailSheet({
    super.key,
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
                Text('ID: ${checklist.id}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 4),
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
                  _SignaturePreview(signatureBase64: checklist.signatureBase64!),
                ],
                if (checklist.notes != null && checklist.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const CorporateSectionTitle(title: 'Observacoes'),
                  Text(checklist.notes!, style: const TextStyle(fontSize: 14, height: 1.35)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      openChecklistPdfViewer(context, checklist);
                    },
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('VER PDF NO APP'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => pdfService.share(checklist),
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('Compartilhar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final savedPath = await pdfService.download(checklist);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('PDF salvo: $savedPath')),
                            );
                          }
                        },
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Baixar'),
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

class _SignaturePreview extends StatelessWidget {
  const _SignaturePreview({required this.signatureBase64});

  final String signatureBase64;

  @override
  Widget build(BuildContext context) {
    try {
      final bytes = base64Decode(signatureBase64);
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Image.memory(bytes, height: 80, fit: BoxFit.contain),
      );
    } catch (_) {
      return const Text('Assinatura registrada no PDF.', style: TextStyle(fontSize: 13));
    }
  }
}
