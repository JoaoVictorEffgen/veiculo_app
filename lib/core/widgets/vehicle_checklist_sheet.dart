import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../shared/models/app_models.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/vehicle_checklist_pdf_service.dart';
import 'corporate_ui.dart';

class VehicleChecklistSheet extends ConsumerStatefulWidget {
  const VehicleChecklistSheet({
    super.key,
    required this.driver,
    required this.vehicle,
  });

  final AppUser driver;
  final Vehicle vehicle;

  static Future<VehicleChecklist?> show(
    BuildContext context, {
    required AppUser driver,
    required Vehicle vehicle,
  }) {
    return Navigator.of(context).push<VehicleChecklist>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VehicleChecklistSheet(driver: driver, vehicle: vehicle),
      ),
    );
  }

  @override
  ConsumerState<VehicleChecklistSheet> createState() => _VehicleChecklistSheetState();
}

class _VehicleChecklistSheetState extends ConsumerState<VehicleChecklistSheet> {
  final _notesController = TextEditingController();
  final _items = <String, bool>{for (final item in VehicleChecklistConfig.items) item.id: false};
  var _saving = false;

  bool get _allChecked => VehicleChecklistConfig.items.every((item) => _items[item.id] == true);

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_allChecked || _saving) return;
    setState(() => _saving = true);

    final error = await ref.read(repositoryProvider).saveVehicleChecklist(
          widget.driver,
          widget.vehicle,
          items: _items,
          notes: _notesController.text,
        );

    if (!mounted) return;
    setState(() => _saving = false);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    final saved = VehicleChecklist(
      id: vehicleChecklistDocId(driverId: widget.driver.id, vehicleId: widget.vehicle.id),
      driverId: widget.driver.id,
      driverName: widget.driver.name,
      vehicleId: widget.vehicle.id,
      vehicleName: widget.vehicle.name,
      vehiclePlate: widget.vehicle.plate,
      vehicleModel: widget.vehicle.model,
      checklistDate: checklistDateKey(),
      items: Map<String, bool>.from(_items),
      completedAt: DateTime.now(),
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );

    await _showPdfActions(saved);
    if (mounted) Navigator.pop(context, saved);
  }

  Future<void> _showPdfActions(VehicleChecklist checklist) async {
    final pdfService = VehicleChecklistPdfService();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Checklist concluido'),
        content: Text(
          'Checklist do ${widget.vehicle.name} registrado com sucesso.\n\n'
          'Voce pode compartilhar ou baixar o PDF antes de iniciar a corrida.',
        ),
        actions: [
          TextButton(
            onPressed: () async => pdfService.share(checklist),
            child: const Text('Compartilhar PDF'),
          ),
          TextButton(
            onPressed: () async {
              final file = await pdfService.download(checklist);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('PDF salvo em: ${file.path}')),
                );
              }
            },
            child: const Text('Baixar PDF'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CHECKLIST DO VEICULO'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _saving ? null : () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              children: [
                const CorporatePageHeader(
                  title: 'Inspecao antes da corrida',
                  subtitle: 'Obrigatorio na primeira vez do veiculo no dia ou ao trocar de veiculo.',
                ),
                const SizedBox(height: 12),
                CorporateSurface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.vehicle.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text('${widget.vehicle.model} • ${widget.vehicle.plate}', style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text('Motorista: ${widget.driver.name}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const CorporateSectionTitle(title: 'Itens de verificacao'),
                ...VehicleChecklistConfig.items.map(
                  (item) => CorporateSurface(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: CheckboxListTile(
                      value: _items[item.id] ?? false,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _items[item.id] = value ?? false),
                      title: Text(item.label, style: const TextStyle(fontSize: 14)),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Observacoes (opcional)',
                    hintText: 'Ex.: arranhão lateral direita',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _allChecked && !_saving ? _submit : null,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.checklist_rtl),
                  label: Text(_saving ? 'Salvando...' : 'CONCLUIR CHECKLIST'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showChecklistPdfOptions(
  BuildContext context,
  VehicleChecklist checklist,
) async {
  final pdfService = VehicleChecklistPdfService();
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('PDF do checklist de hoje'),
      content: Text('Checklist do ${checklist.vehicleName} ja foi feito hoje.'),
      actions: [
        TextButton(
          onPressed: () async => pdfService.share(checklist),
          child: const Text('Compartilhar PDF'),
        ),
        TextButton(
          onPressed: () async {
            final file = await pdfService.download(checklist);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('PDF salvo em: ${file.path}')),
              );
            }
          },
          child: const Text('Baixar PDF'),
        ),
        ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
      ],
    ),
  );
}
