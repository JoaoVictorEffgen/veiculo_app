import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/loading_dialog.dart';
import '../../../../core/widgets/corporate_ui.dart';
import '../../../../core/utils/iterable_extensions.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/app_providers.dart';
import '../../../vehicles/presentation/screens/maintenance_plan_viewer_screen.dart';

Future<void> openVehicleMaintenanceSheet(
  BuildContext context,
  WidgetRef ref, {
  required AppUser admin,
  required Vehicle vehicle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => VehicleMaintenanceSheet(admin: admin, vehicle: vehicle),
  );
}

class VehicleMaintenanceSheet extends ConsumerStatefulWidget {
  const VehicleMaintenanceSheet({
    super.key,
    required this.admin,
    required this.vehicle,
  });

  final AppUser admin;
  final Vehicle vehicle;

  @override
  ConsumerState<VehicleMaintenanceSheet> createState() => _VehicleMaintenanceSheetState();
}

class _VehicleMaintenanceSheetState extends ConsumerState<VehicleMaintenanceSheet> {
  late final TextEditingController _odometerController;
  late final TextEditingController _nextKmController;
  late final TextEditingController _notesController;
  late final TextEditingController _serviceTypeController;
  late final TextEditingController _serviceKmController;
  late final TextEditingController _serviceCostController;
  late final TextEditingController _serviceNotesController;
  DateTime? _nextServiceDate;
  DateTime _serviceDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    final vehicle = widget.vehicle;
    _odometerController = TextEditingController(text: _numText(vehicle.odometerKm));
    _nextKmController = TextEditingController(text: _numText(vehicle.nextServiceKm));
    _notesController = TextEditingController(text: vehicle.lastServiceNotes ?? '');
    _serviceTypeController = TextEditingController();
    _serviceKmController = TextEditingController(text: _numText(vehicle.odometerKm));
    _serviceCostController = TextEditingController();
    _serviceNotesController = TextEditingController();
    _nextServiceDate = vehicle.nextServiceDate;
  }

  String _numText(double? value) => value == null ? '' : value.toStringAsFixed(0);

  double? _parseDouble(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  @override
  void dispose() {
    _odometerController.dispose();
    _nextKmController.dispose();
    _notesController.dispose();
    _serviceTypeController.dispose();
    _serviceKmController.dispose();
    _serviceCostController.dispose();
    _serviceNotesController.dispose();
    super.dispose();
  }

  Vehicle get _vehicle =>
      ref.watch(vehicleControllerProvider).where((item) => item.id == widget.vehicle.id).firstOrNull ?? widget.vehicle;

  Future<void> _saveProfile() async {
    final error = await ref.read(adminControllerProvider.notifier).updateVehicleMaintenance(
          widget.admin,
          widget.vehicle.id,
          odometerKm: _parseDouble(_odometerController.text),
          nextServiceKm: _parseDouble(_nextKmController.text),
          nextServiceDate: _nextServiceDate,
          lastServiceNotes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        );
    ref.read(vehicleControllerProvider.notifier).refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? 'Dados de manutencao salvos.')));
  }

  Future<void> _pickNextServiceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextServiceDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _nextServiceDate = picked);
  }

  Future<void> _pickServiceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _serviceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _serviceDate = picked);
  }

  Future<void> _addLog() async {
    final type = _serviceTypeController.text.trim();
    final km = _parseDouble(_serviceKmController.text);
    if (type.isEmpty || km == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe tipo de servico e odometro.')),
      );
      return;
    }

    final error = await ref.read(adminControllerProvider.notifier).addMaintenanceLog(
          widget.admin,
          widget.vehicle.id,
          serviceDate: _serviceDate,
          odometerKm: km,
          serviceType: type,
          notes: _serviceNotesController.text.trim().isEmpty ? null : _serviceNotesController.text.trim(),
          cost: _parseDouble(_serviceCostController.text),
        );
    ref.read(vehicleControllerProvider.notifier).refresh();
    if (!mounted) return;
    if (error == null) {
      _serviceTypeController.clear();
      _serviceNotesController.clear();
      _serviceCostController.clear();
      setState(() => _serviceDate = DateTime.now());
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? 'Servico registrado.')));
  }

  Future<void> _openPlan() async {
    if (!_vehicle.hasMaintenancePlan) return;
    await openMaintenancePlanViewer(
      context,
      vehicleName: _vehicle.name,
      fileName: _vehicle.maintenancePlanFileName ?? 'plano_manutencao.pdf',
      loadBytes: () async {
        final bytes = await ref.read(repositoryProvider).fetchMaintenancePlanBytes(_vehicle.id);
        if (bytes == null || bytes.isEmpty) throw Exception('Plano nao encontrado.');
        return bytes;
      },
    );
  }

  Future<void> _attachPlan() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (!mounted || picked == null || picked.files.single.bytes == null) return;

    final error = await runWithBlockingLoadingDialog<String?>(
      context,
      message: 'Enviando plano PDF...',
      action: () => ref.read(adminControllerProvider.notifier).uploadMaintenancePlan(
            widget.admin,
            widget.vehicle.id,
            picked.files.single.bytes!,
            picked.files.single.name,
          ),
    );
    ref.read(vehicleControllerProvider.notifier).refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? 'Plano de manutencao anexado.')));
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = _vehicle;
    final logsAsync = ref.watch(maintenanceLogsProvider(vehicle.id));
    final kmUntil = vehicle.kmUntilNextService;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Material(
          color: AppColors.background,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const SizedBox(height: 12),
              Text('Manutencao — ${vehicle.name}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text('${vehicle.model} • ${vehicle.plate}', style: const TextStyle(color: AppColors.textSecondary)),
              if (kmUntil != null) ...[
                const SizedBox(height: 8),
                Text(
                  kmUntil <= 0 ? 'Revisao por km vencida' : 'Proxima revisao em ${kmUntil.toStringAsFixed(0)} km',
                  style: TextStyle(
                    color: kmUntil <= 500 ? AppColors.statusStopped : AppColors.statusMoving,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              CorporateSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const CorporateSectionTitle(title: 'Controle do veiculo'),
                    TextField(
                      controller: _odometerController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Odometro atual (km)', prefixIcon: Icon(Icons.speed_outlined)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nextKmController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Proxima revisao em (km)', prefixIcon: Icon(Icons.build_outlined)),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickNextServiceDate,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        _nextServiceDate == null
                            ? 'Data prevista da revisao (opcional)'
                            : 'Revisao prevista: ${DateFormat('dd/MM/yyyy').format(_nextServiceDate!)}',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Observacoes da ultima manutencao',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (vehicle.lastServiceDate != null)
                      Text(
                        'Ultimo servico: ${formatDateTime(vehicle.lastServiceDate)}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _saveProfile, child: const Text('SALVAR DADOS')),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CorporateSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const CorporateSectionTitle(title: 'Registrar servico'),
                    TextField(
                      controller: _serviceTypeController,
                      decoration: const InputDecoration(labelText: 'Tipo de servico', hintText: 'Ex.: Troca de oleo'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _serviceKmController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Odometro no servico (km)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _serviceCostController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Custo (opcional)', prefixText: 'R\$ '),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _serviceNotesController,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Detalhes (opcional)', alignLabelWithHint: true),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickServiceDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text('Data do servico: ${DateFormat('dd/MM/yyyy').format(_serviceDate)}'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _addLog,
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('REGISTRAR SERVICO'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const CorporateSectionTitle(title: 'Historico de servicos'),
              logsAsync.when(
                loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
                error: (error, _) => Text('Erro ao carregar historico: $error'),
                data: (logs) {
                  if (logs.isEmpty) {
                    return const CorporateEmptyState(message: 'Nenhum servico registrado ainda.');
                  }
                  return Column(
                    children: logs
                        .map(
                          (log) => CorporateSurface(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(Icons.handyman_outlined, color: AppColors.accent),
                              title: Text(log.serviceType, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${formatDateTime(log.serviceDate)} • ${log.odometerKm.toStringAsFixed(0)} km'
                                '${log.cost == null ? '' : ' • R\$ ${log.cost!.toStringAsFixed(2)}'}'
                                '${log.notes == null || log.notes!.isEmpty ? '' : '\n${log.notes}'}',
                              ),
                              isThreeLine: true,
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 16),
              CorporateSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const CorporateSectionTitle(title: 'Plano de manutencao'),
                    Text(
                      vehicle.hasMaintenancePlan
                          ? 'Arquivo: ${vehicle.maintenancePlanFileName}'
                          : 'Nenhum plano de manutencao anexado.',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    if (vehicle.hasMaintenancePlan)
                      OutlinedButton.icon(
                        onPressed: _openPlan,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('VISUALIZAR PDF'),
                      ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _attachPlan,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(vehicle.hasMaintenancePlan ? 'SUBSTITUIR PLANO' : 'ANEXAR PLANO'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
