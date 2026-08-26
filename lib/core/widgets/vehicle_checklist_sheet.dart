import 'dart:convert';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';

import '../../app/theme.dart';
import '../../features/checklists/presentation/screens/checklist_pdf_viewer_screen.dart';
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
  final _signatureController = SignatureController(
    penStrokeWidth: 2.5,
    penColor: AppColors.textPrimary,
    exportBackgroundColor: Colors.white,
  );
  final _items = <String, bool>{for (final item in VehicleChecklistConfig.items) item.id: false};
  var _saving = false;

  int get _missingCount => VehicleChecklistConfig.items.where((item) => _items[item.id] != true).length;

  @override
  void dispose() {
    _notesController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  Future<Uint8List?> _captureSignatureBytes() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    try {
      final bytes = await _signatureController.toPngBytes(width: 360, height: 160);
      if (bytes != null && bytes.isNotEmpty) return bytes;
    } on PlatformException catch (error) {
      debugPrint('Assinatura toPngBytes: $error');
    } catch (error) {
      debugPrint('Assinatura toPngBytes: $error');
    }

    try {
      return await _signatureController.toPngBytes();
    } catch (error) {
      debugPrint('Assinatura fallback toPngBytes: $error');
      return null;
    }
  }

  Future<void> _submit() async {
    if (_saving) return;

    if (_signatureController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assine o checklist antes de concluir.')),
      );
      return;
    }

    final signatureBytes = await _captureSignatureBytes();
    if (signatureBytes == null || signatureBytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nao foi possivel capturar a assinatura. Limpe e assine novamente.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final signatureBase64 = base64Encode(signatureBytes);

    try {
      final error = await ref.read(repositoryProvider).saveVehicleChecklist(
            widget.driver,
            widget.vehicle,
            items: _items,
            notes: _notesController.text,
            signatureBase64: signatureBase64,
          );

      if (!mounted) return;
      setState(() => _saving = false);

      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        return;
      }

      ref.invalidate(driverTodayChecklistsProvider);
      ref.invalidate(vehicleChecklistsProvider);

      final freshDriver = ref.read(authControllerProvider).user ?? widget.driver;
      final saved = VehicleChecklist(
        id: vehicleChecklistDocId(driverId: freshDriver.id, vehicleId: widget.vehicle.id),
        driverId: freshDriver.id,
        driverName: freshDriver.name,
        vehicleId: widget.vehicle.id,
        vehicleName: widget.vehicle.name,
        vehiclePlate: widget.vehicle.plate,
        vehicleModel: widget.vehicle.model,
        checklistDate: checklistDateKey(),
        items: Map<String, bool>.from(_items),
        completedAt: DateTime.now(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        signatureBase64: signatureBase64,
      );

      if (!mounted) return;
      final rootContext = Navigator.of(context, rootNavigator: true).context;
      final messenger = ScaffoldMessenger.of(rootContext);
      Navigator.pop(context, saved);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Checklist registrado com sucesso.'),
          action: SnackBarAction(
            label: 'Ver PDF',
            onPressed: () => unawaited(_showPdfActions(rootContext, saved)),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro inesperado ao salvar checklist: $error')),
      );
    }
  }

  Future<void> _showPdfActions(BuildContext dialogContext, VehicleChecklist checklist) async {
    final pdfService = VehicleChecklistPdfService();
    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Checklist concluido'),
        content: Text(
          'Checklist do ${widget.vehicle.name} registrado com sucesso.\n\n'
          'Voce pode ver o PDF no app ou acessar depois na aba Checklists.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openChecklistPdfViewer(dialogContext, checklist);
            },
            child: const Text('Ver PDF no app'),
          ),
          TextButton(
            onPressed: () async => pdfService.share(checklist),
            child: const Text('Compartilhar'),
          ),
          TextButton(
            onPressed: () async {
              final savedPath = await pdfService.download(checklist);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('PDF salvo: $savedPath')),
                );
              }
            },
            child: const Text('Baixar'),
          ),
          TextButton(
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
                  subtitle: 'Marque o que esta OK. Itens sem marca indicam possivel falta ou problema.',
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
                      subtitle: (_items[item.id] != true)
                          ? const Text('Sem marca = pode estar faltando', style: TextStyle(fontSize: 11))
                          : null,
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
                    hintText: 'Ex.: extintor vencido, pneu careca',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                const CorporateSectionTitle(title: 'Assinatura do motorista'),
                const Text(
                  'Obrigatoria para concluir o checklist.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 8),
                CorporateSurface(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            color: Colors.white,
                          ),
                          child: Signature(
                            controller: _signatureController,
                            height: 180,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _saving ? null : () => _signatureController.clear(),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Limpar assinatura'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_missingCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '$_missingCount item(ns) sem marca — serao registrados como possivel falta no PDF.',
                      style: const TextStyle(color: AppColors.statusStopped, fontSize: 12),
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
                  onPressed: !_saving ? _submit : null,
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
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            openChecklistPdfViewer(context, checklist);
          },
          child: const Text('Ver PDF no app'),
        ),
        TextButton(
          onPressed: () async => pdfService.share(checklist),
          child: const Text('Compartilhar'),
        ),
        TextButton(
          onPressed: () async {
            final savedPath = await pdfService.download(checklist);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('PDF salvo: $savedPath')),
              );
            }
          },
          child: const Text('Baixar'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
      ],
    ),
  );
}
