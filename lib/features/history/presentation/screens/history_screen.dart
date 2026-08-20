import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/corporate_ui.dart';
import '../../../../core/widgets/main_app_shell.dart';
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
    final user = ref.watch(authControllerProvider).user;
    final isAdmin = user?.role == UserRole.admin;
    final title = isAdmin ? 'Historico da frota' : 'Meu historico';

    return movementsAsync.when(
      loading: () => Scaffold(
        appBar: CorporateAppBar(title: title),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: CorporateAppBar(title: title),
        body: Center(child: Text('Erro: $error')),
      ),
      data: (movements) {
        final filtered = _vehicleFilter == null
            ? movements
            : movements.where((movement) => movement.vehicleId == _vehicleFilter).toList();

        return Scaffold(
          appBar: CorporateAppBar(title: title),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: CorporatePageHeader(
                  title: isAdmin ? 'Movimentacoes registradas' : 'Suas movimentacoes',
                  subtitle: '${filtered.length} registro(s) encontrado(s)',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: DropdownButtonFormField<String?>(
                  value: _vehicleFilter,
                  decoration: const InputDecoration(
                    labelText: 'Filtrar por veiculo',
                    prefixIcon: Icon(Icons.filter_list),
                  ),
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
                    ? const CorporateEmptyState(message: 'Nenhuma movimentacao registrada.')
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final movement = filtered[index];
                          final isOn = movement.action == MovementAction.on;
                          final color = isOn ? AppColors.statusMoving : AppColors.statusStopped;
                          return CorporateSurface(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: isOn ? AppColors.statusMovingBg : AppColors.statusStoppedBg,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(isOn ? Icons.play_arrow : Icons.stop, color: color),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${movement.vehicleName} • ${isOn ? 'INICIO' : 'PARADA'}',
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 4),
                                      Text('Motorista: ${movement.driverName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                                      if (movement.location != null)
                                        Text('Local: ${movement.location}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                                    ],
                                  ),
                                ),
                                Text(
                                  formatDateTime(movement.createdAt),
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  textAlign: TextAlign.end,
                                ),
                              ],
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
