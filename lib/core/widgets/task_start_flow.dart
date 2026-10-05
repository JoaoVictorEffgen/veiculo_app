import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/iterable_extensions.dart';
import '../../shared/models/app_models.dart';
import '../../shared/models/navigation_route.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/routing_service.dart';
import 'driver_route_planner_card.dart';
import 'navigation_route_screen.dart';
import 'vehicle_checklist_sheet.dart';

Future<bool> runTaskStartFlow({
  required BuildContext context,
  required WidgetRef ref,
  required AppUser driver,
  required FleetAnnouncement announcement,
}) async {
  final vehicles = ref.read(vehicleControllerProvider);
  final myMoving = vehicles
      .where((vehicle) => vehicle.currentDriverId == driver.id && vehicle.status == VehicleStatus.moving)
      .firstOrNull;

  Vehicle? vehicle = myMoving;
  if (vehicle == null) {
    final stopped = vehicles.where((vehicle) => vehicle.status == VehicleStatus.stopped).toList();
    if (stopped.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum veiculo parado disponivel para iniciar a tarefa.')),
      );
      return false;
    }
    if (!context.mounted) return false;
    vehicle = await _pickVehicle(context, stopped);
    if (vehicle == null) return false;
  }

  if (!context.mounted) return false;
  final checklistOk = await _ensureChecklistForVehicle(context, ref, driver, vehicle);
  if (!checklistOk) return false;

  final trackingService = ref.read(locationTrackingServiceProvider);
  final canTrack = kIsWeb
      ? true
      : await trackingService.canStartTripTracking();
  if (!canTrack) {
    if (!context.mounted) return false;
    final issue = trackingService.permissionIssue ??
        'Permita localizacao "O tempo todo" e desative economia de bateria para este app.';
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GPS necessario'),
        content: Text('$issue\n\nNecessario para iniciar a tarefa com o veiculo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await trackingService.openPermissionSettings();
            },
            child: const Text('Abrir configuracoes'),
          ),
        ],
      ),
    );
    return false;
  }

  NavigationRoutePlan? plannedRoute;
  if (announcement.hasDestination) {
    try {
      plannedRoute = await buildRouteToDestination(ref, announcement: announcement);
    } on RoutingException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
      return false;
    }
    if (plannedRoute == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ative o GPS para calcular a rota ate o destino da tarefa.')),
      );
      return false;
    }
  }

  final routePoints = plannedRoute == null
      ? null
      : [
          for (final point in plannedRoute.points) (lat: point.latitude, lng: point.longitude),
        ];

  final startError = await ref.read(repositoryProvider).startAnnouncement(
        driver,
        announcement.id,
        routePoints: routePoints,
      );
  if (startError != null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(startError)));
    }
    return false;
  }

  if (vehicle.status != VehicleStatus.moving || vehicle.currentDriverId != driver.id) {
    final vehicleError = await ref.read(vehicleControllerProvider.notifier).start(vehicle.id, driver);
    if (vehicleError != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tarefa iniciada, mas falhou ao ligar o veiculo: $vehicleError')),
        );
      }
      return true;
    }
  }

  if (plannedRoute != null && context.mounted) {
    await openNavigationRouteScreen(context, route: plannedRoute);
  }

  return true;
}

Future<Vehicle?> _pickVehicle(BuildContext context, List<Vehicle> vehicles) {
  return showDialog<Vehicle>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Escolha o veiculo'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: vehicles.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final vehicle = vehicles[index];
            return ListTile(
              leading: const Icon(Icons.directions_car_outlined),
              title: Text(vehicle.name),
              subtitle: Text('${vehicle.model} • ${vehicle.plate}'),
              onTap: () => Navigator.pop(context, vehicle),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      ],
    ),
  );
}

Future<bool> _ensureChecklistForVehicle(
  BuildContext context,
  WidgetRef ref,
  AppUser driver,
  Vehicle vehicle,
) async {
  if (!driver.mustCompleteVehicleChecklist) return true;

  var todayChecklist = await fetchTodayChecklistForVehicle(ref, driver, vehicle.id);

  if (todayChecklist == null) {
    final completed = await VehicleChecklistSheet.show(
      context,
      driver: driver,
      vehicle: vehicle,
    );
    if (completed != null) {
      ref.invalidate(driverTodayChecklistsProvider);
    }
    return completed != null;
  }

  final action = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Checklist ja feito hoje'),
      content: Text(
        'Voce ja concluiu o checklist do ${vehicle.name} hoje.\n\n'
        'Deseja iniciar a tarefa ou ver o PDF do checklist?',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(context, 'pdf'), child: const Text('Ver PDF')),
        ElevatedButton(onPressed: () => Navigator.pop(context, 'start'), child: const Text('Continuar')),
      ],
    ),
  );

  if (action == 'pdf') {
    if (context.mounted) await showChecklistPdfOptions(context, todayChecklist);
    return false;
  }

  return action == 'start';
}
