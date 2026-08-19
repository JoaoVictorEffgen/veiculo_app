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
    final drivers = ref.watch(repositoryProvider).users.where((item) => item.role == UserRole.driver).toList();
    final moving = vehicles.where((item) => item.status == VehicleStatus.moving).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel administrativo'),
        actions: [
          IconButton(onPressed: () => context.push(AppRoutes.dashboard), icon: const Icon(Icons.directions_car_filled_outlined), tooltip: 'Operar veículos'),
          IconButton(onPressed: () => context.push(AppRoutes.history), icon: const Icon(Icons.history), tooltip: 'Histórico'),
          IconButton(onPressed: () { ref.read(authControllerProvider.notifier).logout(); context.go(AppRoutes.login); }, icon: const Icon(Icons.logout), tooltip: 'Sair'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
        children: [
          Text('Visão geral', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: () => context.push(AppRoutes.dashboard), icon: const Icon(Icons.directions_car_filled_outlined), label: const Text('OPERAR VEÍCULOS')),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _chooseCreate(context, ref, user!), icon: const Icon(Icons.add_circle_outline), label: const Text('CADASTRAR'))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(onPressed: () => _chooseDelete(context, ref, user!), icon: const Icon(Icons.delete_outline), label: const Text('EXCLUIR'))),
          ]),
          const SizedBox(height: 24),
          Row(children: [
            _SummaryCard(label: 'Veículos', value: '${vehicles.length}', icon: Icons.local_shipping_outlined),
            _SummaryCard(label: 'Em uso', value: '$moving', icon: Icons.directions_car_filled, color: AppColors.statusMoving),
            _SummaryCard(label: 'Motoristas', value: '${drivers.length}', icon: Icons.people_outline),
          ]),
          const SizedBox(height: 24),
          Text('Veículos cadastrados', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...vehicles.map((vehicle) => Card(child: ListTile(
                leading: Icon(vehicle.status == VehicleStatus.moving ? Icons.circle : Icons.circle_outlined, color: vehicle.status == VehicleStatus.moving ? AppColors.statusMoving : AppColors.statusStopped),
                title: Text(vehicle.name),
                subtitle: Text('${vehicle.model} • ${vehicle.plate}\n${vehicle.currentDriverName ?? 'Disponível'}${vehicle.stoppedLocation == null ? '' : ' • ${vehicle.stoppedLocation}'}'),
                isThreeLine: true,
                trailing: const Icon(Icons.visibility_outlined),
              ))),
          const SizedBox(height: 24),
          Text('Motoristas cadastrados', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...drivers.map((driver) => Card(child: ListTile(leading: const Icon(Icons.person_outline), title: Text(driver.name), subtitle: Text(driver.email), trailing: const Icon(Icons.verified_user_outlined)))),
        ],
      ),
    );
  }

  Future<void> _chooseCreate(BuildContext context, WidgetRef ref, AppUser admin) async {
    final choice = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: const Text('O que deseja cadastrar?'), content: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: const Icon(Icons.local_shipping_outlined), title: const Text('Veículo'), onTap: () => Navigator.pop(context, 'vehicle')), ListTile(leading: const Icon(Icons.person_add_alt_1), title: const Text('Motorista'), onTap: () => Navigator.pop(context, 'driver'))])));
    if (!context.mounted) return;
    if (choice == 'vehicle') {
      await _addVehicle(context, ref, admin);
    } else if (choice == 'driver') {
      await _addDriver(context, ref, admin);
    }
  }

  Future<void> _chooseDelete(BuildContext context, WidgetRef ref, AppUser admin) async {
    final choice = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: const Text('O que deseja excluir?'), content: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: const Icon(Icons.local_shipping_outlined), title: const Text('Veículo'), onTap: () => Navigator.pop(context, 'vehicle')), ListTile(leading: const Icon(Icons.person_outline), title: const Text('Motorista'), onTap: () => Navigator.pop(context, 'driver'))])));
    if (!context.mounted || choice == null) return;
    if (choice == 'vehicle') {
      final vehicle = await _selectVehicle(context, ref.watch(vehicleControllerProvider));
      if (vehicle != null && context.mounted) await _deleteVehicle(context, ref, admin, vehicle);
    } else {
      final driver = await _selectDriver(context, ref.watch(repositoryProvider).users.where((item) => item.role == UserRole.driver).toList());
      if (driver != null && context.mounted) await _deleteDriver(context, ref, admin, driver);
    }
  }

  Future<Vehicle?> _selectVehicle(BuildContext context, List<Vehicle> vehicles) => showDialog<Vehicle>(context: context, builder: (context) => AlertDialog(title: const Text('Selecione o veículo'), content: SizedBox(width: double.maxFinite, child: ListView(shrinkWrap: true, children: vehicles.map((vehicle) => ListTile(title: Text(vehicle.name), subtitle: Text(vehicle.plate), onTap: () => Navigator.pop(context, vehicle))).toList()))));

  Future<AppUser?> _selectDriver(BuildContext context, List<AppUser> drivers) => showDialog<AppUser>(context: context, builder: (context) => AlertDialog(title: const Text('Selecione o motorista'), content: SizedBox(width: double.maxFinite, child: ListView(shrinkWrap: true, children: drivers.map((driver) => ListTile(title: Text(driver.name), subtitle: Text(driver.email), onTap: () => Navigator.pop(context, driver))).toList()))));

  Future<void> _addVehicle(BuildContext context, WidgetRef ref, AppUser admin) async {
    final values = await _vehicleForm(context, title: 'Adicionar veículo');
    if (values == null || !context.mounted) return;
    final error = ref.read(adminControllerProvider.notifier).addVehicle(admin, name: values[0], model: values[1], plate: values[2]);
    ref.read(vehicleControllerProvider.notifier).refresh();
    if (error != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _deleteVehicle(BuildContext context, WidgetRef ref, AppUser admin, Vehicle vehicle) async {
    final confirmed = await _confirmDelete(context, 'Excluir ${vehicle.name}?');
    if (!confirmed || !context.mounted) return;
    final error = ref.read(adminControllerProvider.notifier).deleteVehicle(admin, vehicle.id);
    ref.read(vehicleControllerProvider.notifier).refresh();
    if (error != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _addDriver(BuildContext context, WidgetRef ref, AppUser admin) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController(text: '123456');
    final values = await showDialog<List<String>>(context: context, builder: (context) => AlertDialog(title: const Text('Adicionar motorista'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome')), TextField(controller: email, decoration: const InputDecoration(labelText: 'E-mail')), TextField(controller: password, decoration: const InputDecoration(labelText: 'Senha'))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), ElevatedButton(onPressed: () { if (name.text.trim().isNotEmpty && email.text.trim().isNotEmpty && password.text.isNotEmpty) Navigator.pop(context, [name.text, email.text, password.text]); }, child: const Text('Cadastrar'))]));
    name.dispose();
    email.dispose();
    password.dispose();
    if (values == null || !context.mounted) return;
    final error = ref.read(adminControllerProvider.notifier).addDriver(admin, name: values[0], email: values[1], password: values[2]);
    if (error != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _deleteDriver(BuildContext context, WidgetRef ref, AppUser admin, AppUser driver) async {
    final confirmed = await _confirmDelete(context, 'Excluir ${driver.name}?');
    if (!confirmed || !context.mounted) return;
    final error = ref.read(adminControllerProvider.notifier).deleteDriver(admin, driver.id);
    if (error != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<bool> _confirmDelete(BuildContext context, String title) async => await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text(title), content: const Text('Essa ação não poderá ser desfeita.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Excluir'))])) ?? false;

  Future<List<String>?> _vehicleForm(BuildContext context, {required String title}) async {
    final name = TextEditingController();
    final model = TextEditingController();
    final plate = TextEditingController();
    final result = await showDialog<List<String>>(context: context, builder: (context) => AlertDialog(title: Text(title), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome / código')), TextField(controller: model, decoration: const InputDecoration(labelText: 'Modelo')), TextField(controller: plate, decoration: const InputDecoration(labelText: 'Placa'))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')), ElevatedButton(onPressed: () { if (name.text.trim().isNotEmpty && model.text.trim().isNotEmpty && plate.text.trim().isNotEmpty) Navigator.pop(context, [name.text, model.text, plate.text]); }, child: const Text('Cadastrar'))]));
    name.dispose();
    model.dispose();
    plate.dispose();
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
  Widget build(BuildContext context) => Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [Icon(icon, color: color ?? AppColors.primary), const SizedBox(height: 6), Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))]))));
}
