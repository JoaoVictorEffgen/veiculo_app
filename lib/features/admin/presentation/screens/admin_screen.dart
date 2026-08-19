import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/app_providers.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    if (user?.role != UserRole.admin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Acesso negado')),
        body: Center(child: ElevatedButton(onPressed: () => context.go(AppRoutes.dashboard), child: const Text('Voltar'))),
      );
    }

    ref.watch(adminControllerProvider);
    final vehicles = ref.watch(vehicleControllerProvider);
    final drivers = ref.watch(usersProvider).where((item) => item.role == UserRole.driver).toList();
    final moving = vehicles.where((item) => item.status == VehicleStatus.moving).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel administrativo'),
        actions: [
          IconButton(onPressed: () => context.push(AppRoutes.dashboard), icon: const Icon(Icons.directions_car_filled_outlined), tooltip: 'Operar veiculos'),
          IconButton(onPressed: () => context.push(AppRoutes.history), icon: const Icon(Icons.history), tooltip: 'Historico'),
          IconButton(
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go(AppRoutes.login);
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
        children: [
          Text('Visao geral', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: () => context.push(AppRoutes.dashboard), icon: const Icon(Icons.directions_car_filled_outlined), label: const Text('OPERAR VEICULOS')),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _chooseCreate(context, ref, user!), icon: const Icon(Icons.add_circle_outline), label: const Text('CADASTRAR'))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(onPressed: () => _chooseEdit(context, ref, user!), icon: const Icon(Icons.edit_outlined), label: const Text('EDITAR'))),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: () => _chooseDelete(context, ref, user!), icon: const Icon(Icons.delete_outline), label: const Text('EXCLUIR')),
          const SizedBox(height: 24),
          Row(children: [
            _SummaryCard(label: 'Veiculos', value: '${vehicles.length}', icon: Icons.local_shipping_outlined),
            _SummaryCard(label: 'Em uso', value: '$moving', icon: Icons.directions_car_filled, color: AppColors.statusMoving),
            _SummaryCard(label: 'Motoristas', value: '${drivers.length}', icon: Icons.people_outline),
          ]),
          const SizedBox(height: 24),
          Text('Veiculos cadastrados', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...vehicles.map((vehicle) => Card(
                child: ListTile(
                  leading: Icon(
                    vehicle.status == VehicleStatus.moving ? Icons.circle : Icons.circle_outlined,
                    color: vehicle.status == VehicleStatus.moving ? AppColors.statusMoving : AppColors.statusStopped,
                  ),
                  title: Text(vehicle.name),
                  subtitle: Text('${vehicle.model} • ${vehicle.plate}\n${vehicle.currentDriverName ?? 'Disponivel'}${vehicle.stoppedLocation == null ? '' : ' • ${vehicle.stoppedLocation}'}'),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editVehicle(context, ref, user!, vehicle),
                  ),
                ),
              )),
          const SizedBox(height: 24),
          Text('Motoristas cadastrados', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...drivers.map((driver) => Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(driver.name),
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
      final driver = await _selectDriver(context, ref.watch(usersProvider).where((item) => item.role == UserRole.driver).toList());
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
      final driver = await _selectDriver(context, ref.watch(usersProvider).where((item) => item.role == UserRole.driver).toList());
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
    ref.read(vehicleControllerProvider.notifier).refresh();
    if (error != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _deleteVehicle(BuildContext context, WidgetRef ref, AppUser admin, Vehicle vehicle) async {
    final confirmed = await _confirmDelete(context, 'Excluir ${vehicle.name}?');
    if (!confirmed || !context.mounted) return;
    final error = await ref.read(adminControllerProvider.notifier).deleteVehicle(admin, vehicle.id);
    ref.read(vehicleControllerProvider.notifier).refresh();
    if (error != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _addDriver(BuildContext context, WidgetRef ref, AppUser admin) async {
    final values = await _driverForm(context, title: 'Adicionar motorista');
    if (values == null || !context.mounted) return;
    final error = await ref.read(adminControllerProvider.notifier).addDriver(admin, name: values[0], email: values[1], password: values[2]);
    if (error != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _editDriver(BuildContext context, WidgetRef ref, AppUser admin, AppUser driver) async {
    final values = await _driverForm(context, title: 'Editar motorista', initialName: driver.name, initialEmail: driver.email, initialPassword: driver.password);
    if (values == null || !context.mounted) return;
    final error = await ref.read(adminControllerProvider.notifier).editDriver(admin, driverId: driver.id, name: values[0], email: values[1], password: values[2]);
    if (error != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
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
    String? initialPassword,
  }) async {
    final name = TextEditingController(text: initialName);
    final email = TextEditingController(text: initialEmail);
    final password = TextEditingController(text: initialPassword);
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
              TextField(controller: password, decoration: const InputDecoration(labelText: 'Senha')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty && email.text.trim().isNotEmpty && password.text.isNotEmpty) {
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value, required this.icon, this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Icon(icon, color: color ?? AppColors.primary),
                const SizedBox(height: 6),
                Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      );
}
