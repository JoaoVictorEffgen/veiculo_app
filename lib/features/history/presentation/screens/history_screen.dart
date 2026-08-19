import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/date_formatter.dart';
import '../../../../shared/services/app_providers.dart';
import '../../../../shared/models/app_models.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movements = ref.watch(movementsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico')),
      body: movements.isEmpty
          ? const Center(child: Text('Nenhuma movimentação registrada.'))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: movements.length,
              itemBuilder: (context, index) {
                final movement = movements[index];
                final isOn = movement.action == MovementAction.on;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isOn ? Colors.green.shade50 : Colors.red.shade50,
                      child: Icon(isOn ? Icons.play_arrow : Icons.stop, color: isOn ? Colors.green : Colors.red),
                    ),
                    title: Text('${movement.vehicleName} - ${isOn ? 'INICIO' : 'PARADA'}'),
                    subtitle: Text('${movement.driverName}${movement.location == null ? '' : '\nLocal: ${movement.location}'}'),
                    isThreeLine: movement.location != null,
                    trailing: Text(formatDateTime(movement.createdAt), textAlign: TextAlign.end),
                  ),
                );
              },
            ),
    );
  }
}
