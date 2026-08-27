import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/loading_dialog.dart';
import '../../../../core/widgets/corporate_ui.dart';
import '../../../../core/widgets/fleet_announcement_banner.dart';
import '../../../../core/widgets/main_app_shell.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/app_providers.dart';
import '../widgets/vehicle_maintenance_sheet.dart';
import '../../../vehicles/presentation/screens/maintenance_plan_viewer_screen.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    if (user?.role != UserRole.admin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Acesso negado')),
        body: Center(child: ElevatedButton(onPressed: () => context.go(AppRoutes.dashboard), child: const Text('Voltar'))),
      );
    }

    ref.watch(adminControllerProvider);
    final vehicles = ref.watch(vehicleControllerProvider);
    final users = ref.watch(usersProvider).valueOrNull ?? [];
    final drivers = users.where((item) => item.role == UserRole.driver).toList();
    final moving = vehicles.where((item) => item.status == VehicleStatus.moving).length;

    return Scaffold(
      appBar: const CorporateAppBar(title: 'Menu administrativo', showFleetRefresh: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Text('Gestao da frota', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Cadastre, edite e acompanhe veiculos e motoristas.', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          FleetAnnouncementEditor(admin: user!),
          const SizedBox(height: 20),
          CorporateSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CorporateSectionTitle(title: 'Checklists da frota'),
                const Text(
                  'Historico de inspecoes feitas pelos motoristas antes de iniciar a corrida.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => context.go(AppRoutes.checklists),
                  icon: const Icon(Icons.checklist_rtl),
                  label: const Text('VER HISTORICO DE CHECKLISTS'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          CorporateSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(child: ElevatedButton.icon(onPressed: () => _chooseCreate(context, ref, user!), icon: const Icon(Icons.add_circle_outline), label: const Text('CADASTRAR'))),
                  const SizedBox(width: 12),
                  Expanded(child: OutlinedButton.icon(onPressed: () => _chooseEdit(context, ref, user!), icon: const Icon(Icons.edit_outlined), label: const Text('EDITAR'))),
                ]),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: () => _chooseDelete(context, ref, user!), icon: const Icon(Icons.delete_outline), label: const Text('EXCLUIR')),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: CorporateMetricTile(label: 'Veiculos', value: '${vehicles.length}', icon: Icons.local_shipping_outlined)),
            const SizedBox(width: 8),
            Expanded(child: CorporateMetricTile(label: 'Em uso', value: '$moving', icon: Icons.directions_car_filled, color: AppColors.statusMoving)),
            const SizedBox(width: 8),
            Expanded(child: CorporateMetricTile(label: 'Motoristas', value: '${drivers.length}', icon: Icons.people_outline)),
          ]),
          const SizedBox(height: 24),
          const CorporateSectionTitle(title: 'Veiculos cadastrados'),
          const SizedBox(height: 10),
          ...vehicles.map((vehicle) => CorporateSurface(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    vehicle.status == VehicleStatus.moving ? Icons.circle : Icons.circle_outlined,
                    color: vehicle.status == VehicleStatus.moving ? AppColors.statusMoving : AppColors.statusStopped,
                  ),
                  title: Text(vehicle.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${vehicle.model} • ${vehicle.plate}\n'
                    '${vehicle.currentDriverName ?? 'Disponivel'}${vehicle.stoppedLocation == null ? '' : ' • ${vehicle.stoppedLocation}'}\n'
                    '${vehicle.odometerKm != null ? 'Odometro: ${vehicle.odometerKm!.toStringAsFixed(0)} km • ' : ''}'
                    '${vehicle.hasMaintenancePlan ? 'Plano PDF anexado' : 'Sem plano PDF'}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Manutencao',
                        icon: Icon(
                          Icons.build_circle,
                          color: vehicle.kmUntilNextService != null && vehicle.kmUntilNextService! <= 500
                              ? AppColors.statusStopped
                              : (vehicle.hasStructuredMaintenance || vehicle.hasMaintenancePlan)
                                  ? AppColors.statusMoving
                                  : null,
                        ),
                        onPressed: () => openVehicleMaintenanceSheet(context, ref, admin: user!, vehicle: vehicle),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editVehicle(context, ref, user!, vehicle),
                      ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 24),
          const CorporateSectionTitle(title: 'Motoristas cadastrados'),
          ...drivers.map((driver) => CorporateSurface(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(driver.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(driver.email),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editDriver(context, ref, user!, driver),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Future<void> _chooseCreate(BuildContext context, WidgetRef ref, AppUser admin) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('O que deseja cadastrar?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.local_shipping_outlined), title: const Text('Veiculo'), onTap: () => Navigator.pop(context, 'vehicle')),
            ListTile(leading: const Icon(Icons.person_add_alt_1), title: const Text('Motorista'), onTap: () => Navigator.pop(context, 'driver')),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'vehicle') {
      await _addVehicle(context, ref, admin);
    } else if (choice == 'driver') {
      await _addDriver(context, ref, admin);
    }
  }

  Future<void> _chooseEdit(BuildContext context, WidgetRef ref, AppUser admin) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('O que deseja editar?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.local_shipping_outlined), title: const Text('Veiculo'), onTap: () => Navigator.pop(context, 'vehicle')),
            ListTile(leading: const Icon(Icons.person_outline), title: const Text('Motorista'), onTap: () => Navigator.pop(context, 'driver')),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'vehicle') {
      final vehicle = await _selectVehicle(context, ref.watch(vehicleControllerProvider));
      if (vehicle != null && context.mounted) await _editVehicle(context, ref, admin, vehicle);
    } else {
      final driver = await _selectDriver(context, (ref.watch(usersProvider).valueOrNull ?? []).where((item) => item.role == UserRole.driver).toList());
      if (driver != null && context.mounted) await _editDriver(context, ref, admin, driver);
    }
  }

  Future<void> _chooseDelete(BuildContext context, WidgetRef ref, AppUser admin) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('O que deseja excluir?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.local_shipping_outlined), title: const Text('Veiculo'), onTap: () => Navigator.pop(context, 'vehicle')),
            ListTile(leading: const Icon(Icons.person_outline), title: const Text('Motorista'), onTap: () => Navigator.pop(context, 'driver')),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'vehicle') {
      final vehicle = await _selectVehicle(context, ref.watch(vehicleControllerProvider));
      if (vehicle != null && context.mounted) await _deleteVehicle(context, ref, admin, vehicle);
    } else {
      final driver = await _selectDriver(context, (ref.watch(usersProvider).valueOrNull ?? []).where((item) => item.role == UserRole.driver).toList());
      if (driver != null && context.mounted) await _deleteDriver(context, ref, admin, driver);
    }
  }

  Future<Vehicle?> _selectVehicle(BuildContext context, List<Vehicle> vehicles) => showDialog<Vehicle>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Selecione o veiculo'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: vehicles
                  .map((vehicle) => ListTile(title: Text(vehicle.name), subtitle: Text(vehicle.plate), onTap: () => Navigator.pop(context, vehicle)))
                  .toList(),
            ),
          ),
        ),
      );

  Future<AppUser?> _selectDriver(BuildContext context, List<AppUser> drivers) => showDialog<AppUser>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Selecione o motorista'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: drivers.map((driver) => ListTile(title: Text(driver.name), subtitle: Text(driver.email), onTap: () => Navigator.pop(context, driver))).toList(),
            ),
          ),
        ),
      );

  Future<void> _addVehicle(BuildContext context, WidgetRef ref, AppUser admin) async {
    final values = await _vehicleForm(context, title: 'Adicionar veiculo');
    if (values == null || !context.mounted) return;
    final error = await ref.read(adminControllerProvider.notifier).addVehicle(admin, name: values[0], model: values[1], plate: values[2]);
    ref.read(vehicleControllerProvider.notifier).refresh();
    if (error != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _editVehicle(BuildContext context, WidgetRef ref, AppUser admin, Vehicle vehicle) async {
    final values = await _vehicleForm(
      context,
      title: 'Editar veiculo',
      initialName: vehicle.name,
      initialModel: vehicle.model,
      initialPlate: vehicle.plate,
    );
    if (values == null || !context.mounted) return;
    final error = await ref.read(adminControllerProvider.notifier).editVehicle(admin, vehicleId: vehicle.id, name: values[0], model: values[1], plate: values[2]);
    await refreshFleetSnapshot(ref);
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Veiculo atualizado.')));
    }
  }

  Future<void> _deleteVehicle(BuildContext context, WidgetRef ref, AppUser admin, Vehicle vehicle) async {
    final confirmed = await _confirmDelete(context, 'Excluir ${vehicle.name}?');
    if (!confirmed || !context.mounted) return;
    final error = await ref.read(adminControllerProvider.notifier).deleteVehicle(admin, vehicle.id);
    ref.read(vehicleControllerProvider.notifier).refresh();
    if (error != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _manageMaintenancePlan(BuildContext context, WidgetRef ref, AppUser admin, Vehicle vehicle) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Plano de manutencao — ${vehicle.name}'),
        content: Text(
          vehicle.hasMaintenancePlan
              ? 'Arquivo: ${vehicle.maintenancePlanFileName}\n'
                  'Tamanho: ${((vehicle.maintenancePlanSizeBytes ?? 0) / 1024).toStringAsFixed(0)} KB\n'
                  'Atualizado: ${vehicle.maintenancePlanUpdatedAt == null ? '—' : formatDateTime(vehicle.maintenancePlanUpdatedAt)}'
              : 'Nenhum plano anexado. Escolha um PDF do celular ou computador.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
          if (vehicle.hasMaintenancePlan) ...[
            TextButton(onPressed: () => Navigator.pop(context, 'view'), child: const Text('Visualizar')),
            TextButton(onPressed: () => Navigator.pop(context, 'remove'), child: const Text('Remover')),
          ],
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'attach'),
            child: Text(vehicle.hasMaintenancePlan ? 'Substituir PDF' : 'Anexar PDF'),
          ),
        ],
      ),
    );
    if (!context.mounted || action == null) return;

    if (action == 'view') {
      await _openMaintenancePlan(context, ref, vehicle);
      return;
    }

    if (action == 'remove') {
      final confirmed = await _confirmDelete(context, 'Remover plano de ${vehicle.name}?');
      if (!confirmed || !context.mounted) return;
      final error = await ref.read(adminControllerProvider.notifier).removeMaintenancePlan(admin, vehicle.id);
      ref.read(vehicleControllerProvider.notifier).refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? 'Plano removido.')));
      }
      return;
    }

    if (action == 'attach') {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (!context.mounted) return;
      final file = picked?.files.single;
      if (file == null || file.bytes == null) return;

      final error = await runWithBlockingLoadingDialog<String?>(
        context,
        message: 'Enviando plano de manutencao...',
        action: () => ref.read(adminControllerProvider.notifier).uploadMaintenancePlan(
              admin,
              vehicle.id,
              file.bytes!,
              file.name,
            ),
      );

      ref.read(vehicleControllerProvider.notifier).refresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error ?? 'Plano de manutencao anexado.')),
        );
      }
    }
  }

  Future<void> _openMaintenancePlan(BuildContext context, WidgetRef ref, Vehicle vehicle) async {
    if (!vehicle.hasMaintenancePlan) return;

    await openMaintenancePlanViewer(
      context,
      vehicleName: vehicle.name,
      fileName: vehicle.maintenancePlanFileName ?? 'plano_manutencao.pdf',
      loadBytes: () async {
        final bytes = await ref.read(repositoryProvider).fetchMaintenancePlanBytes(vehicle.id);
        if (bytes == null || bytes.isEmpty) {
          throw Exception('Plano de manutencao nao encontrado.');
        }
        return bytes;
      },
    );
  }

  Future<void> _addDriver(BuildContext context, WidgetRef ref, AppUser admin) async {
    final values = await _driverForm(context, title: 'Adicionar motorista');
    if (values == null || !context.mounted) return;
    final error = await ref.read(adminControllerProvider.notifier).addDriver(admin, name: values[0], email: values[1], password: values[2]);
    if (error != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _editDriver(BuildContext context, WidgetRef ref, AppUser admin, AppUser driver) async {
    final values = await _driverForm(
      context,
      title: 'Editar motorista',
      initialName: driver.name,
      initialEmail: driver.email,
      passwordOptional: true,
    );
    if (values == null || !context.mounted) return;
    final error = await ref.read(adminControllerProvider.notifier).editDriver(
          admin,
          driverId: driver.id,
          name: values[0],
          email: values[1],
          password: values[2].isEmpty ? null : values[2],
        );
    await refreshFleetSnapshot(ref);
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Motorista atualizado.')));
    }
  }

  Future<void> _deleteDriver(BuildContext context, WidgetRef ref, AppUser admin, AppUser driver) async {
    final confirmed = await _confirmDelete(context, 'Excluir ${driver.name}?');
    if (!confirmed || !context.mounted) return;
    final error = await ref.read(adminControllerProvider.notifier).deleteDriver(admin, driver.id);
    if (error != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<bool> _confirmDelete(BuildContext context, String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: const Text('Essa acao nao podera ser desfeita.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir')),
          ],
        ),
      ) ??
      false;

  Future<List<String>?> _vehicleForm(
    BuildContext context, {
    required String title,
    String? initialName,
    String? initialModel,
    String? initialPlate,
  }) async {
    final name = TextEditingController(text: initialName);
    final model = TextEditingController(text: initialModel);
    final plate = TextEditingController(text: initialPlate);
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome / codigo')),
              TextField(controller: model, decoration: const InputDecoration(labelText: 'Modelo')),
              TextField(controller: plate, decoration: const InputDecoration(labelText: 'Placa')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty && model.text.trim().isNotEmpty && plate.text.trim().isNotEmpty) {
                Navigator.pop(context, [name.text, model.text, plate.text]);
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    name.dispose();
    model.dispose();
    plate.dispose();
    return result;
  }

  Future<List<String>?> _driverForm(
    BuildContext context, {
    required String title,
    String? initialName,
    String? initialEmail,
    bool passwordOptional = false,
  }) async {
    final name = TextEditingController(text: initialName);
    final email = TextEditingController(text: initialEmail);
    final password = TextEditingController();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome')),
              TextField(controller: email, decoration: const InputDecoration(labelText: 'E-mail')),
              TextField(
                controller: password,
                decoration: InputDecoration(
                  labelText: passwordOptional ? 'Nova senha (opcional)' : 'Senha',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final hasPassword = password.text.isNotEmpty;
              if (name.text.trim().isNotEmpty && email.text.trim().isNotEmpty && (passwordOptional || hasPassword)) {
                Navigator.pop(context, [name.text, email.text, password.text]);
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    name.dispose();
    email.dispose();
    password.dispose();
    return result;
  }
}
