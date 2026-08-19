import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/app_providers.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String? _vehicleFilter;

  @override
  Widget build(BuildContext context) {
    final movementsAsync = ref.watch(movementsProvider);
    final vehicles = ref.watch(vehicleControllerProvider);

    return movementsAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(appBar: AppBar(title: const Text('Historico')), body: Center(child: Text('Erro: $error'))),
      data: (movements) {
        final filtered = _vehicleFilter == null
            ? movements
            : movements.where((movement) => movement.vehicleId == _vehicleFilter).toList();

        return Scaffold(
          appBar: AppBar(title: const Text('Historico')),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: DropdownButtonFormField<String?>(
                  initialValue: _vehicleFilter,
                  decoration: const InputDecoration(labelText: 'Filtrar por veiculo', prefixIcon: Icon(Icons.filter_list)),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Todos os veiculos')),
                    ...vehicles.map(
                      (vehicle) => DropdownMenuItem<String?>(
                        value: vehicle.id,
                        child: Text(vehicle.name),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _vehicleFilter = value),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('Nenhuma movimentacao registrada.'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final movement = filtered[index];
                          final isOn = movement.action == MovementAction.on;
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isOn ? AppColors.statusMovingBg : AppColors.statusStoppedBg,
                                child: Icon(isOn ? Icons.play_arrow : Icons.stop, color: isOn ? AppColors.statusMoving : AppColors.statusStopped),
                              ),
                              title: Text('${movement.vehicleName} - ${isOn ? 'ON' : 'OFF'}'),
                              subtitle: Text('${movement.driverName}${movement.location == null ? '' : '\nLocal: ${movement.location}'}'),
                              isThreeLine: movement.location != null,
                              trailing: Text(formatDateTime(movement.createdAt), textAlign: TextAlign.end),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
