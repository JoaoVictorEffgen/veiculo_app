import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/loading_dialog.dart';
import '../../../../core/widgets/fleet_announcement_banner.dart';
import '../../../../core/widgets/main_app_shell.dart';
import '../../../../core/widgets/vehicle_checklist_sheet.dart';
import '../../../../core/widgets/vehicle_location_map_preview.dart';
import '../../../../core/utils/iterable_extensions.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/app_providers.dart';
import 'maintenance_plan_viewer_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final vehicles = ref.watch(vehicleControllerProvider);
    final moving = vehicles.where((vehicle) => vehicle.status == VehicleStatus.moving).toList();
    final stopped = vehicles.where((vehicle) => vehicle.status == VehicleStatus.stopped).toList();
    final myVehicle = vehicles
        .where((vehicle) => vehicle.currentDriverId == user?.id && vehicle.status == VehicleStatus.moving)
        .firstOrNull;
    final myTrack = ref.watch(driverTracksProvider).valueOrNull?.where((track) => track.driverId == user?.id).firstOrNull;
    final isAdmin = user?.role == UserRole.admin;
    if (user?.mustCompleteVehicleChecklist == true) {
      ref.watch(driverTodayChecklistsProvider);
    }

    return Scaffold(
      appBar: CorporateAppBar(
        title: isAdmin ? 'Area administrativa' : 'Veiculos',
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.read(vehicleControllerProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            Text(
              'Ola, ${user?.name ?? 'motorista'}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${moving.length} em movimento • ${stopped.length} parados',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            const FleetAnnouncementBanner(),
            if (isAdmin && user != null) ...[
              const SizedBox(height: 16),
              FleetAnnouncementEditor(admin: user),
            ],
            if (myVehicle != null) ...[
              const SizedBox(height: 16),
              _ActiveTripBanner(
                vehicle: myVehicle,
                myTrack: myTrack,
                permissionIssue: ref.read(locationTrackingServiceProvider).permissionIssue,
                onOpenSettings: () => ref.read(locationTrackingServiceProvider).openPermissionSettings(),
              ),
            ],
            const SizedBox(height: 20),
            FleetSection(
              title: 'EM MOVIMENTO',
              count: moving.length,
              headerColor: AppColors.statusMoving,
              children: moving.isEmpty
                  ? [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Nenhum veiculo em movimento no momento.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ]
                  : moving.map((vehicle) => _VehicleCard(vehicle: vehicle, user: user, ref: ref)).toList(),
            ),
            FleetSection(
              title: 'PARADOS / DISPONIVEIS',
              count: stopped.length,
              headerColor: AppColors.statusStopped,
              children: stopped.isEmpty
                  ? [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Nenhum veiculo parado cadastrado.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ]
                  : stopped.map((vehicle) => _VehicleCard(vehicle: vehicle, user: user, ref: ref)).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveTripBanner extends StatelessWidget {
  const _ActiveTripBanner({
    required this.vehicle,
    required this.myTrack,
    required this.permissionIssue,
    required this.onOpenSettings,
  });

  final Vehicle vehicle;
  final DriverTrack? myTrack;
  final String? permissionIssue;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.statusMovingBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.statusMoving.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_car_filled, color: AppColors.statusMoving),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Voce esta usando ${vehicle.name}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.statusMovingDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Desde ${formatDateTime(vehicle.startedAt)}', style: const TextStyle(fontSize: 13)),
          if (myTrack != null)
            Text(
              'Velocidade: ${myTrack!.speedKmh.toStringAsFixed(0)} km/h • GPS ativo',
              style: const TextStyle(color: AppColors.statusMoving, fontWeight: FontWeight.w600, fontSize: 13),
            )
          else
            const Text('Aguardando sinal GPS...', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          const Text(
            'A corrida so encerra ao tocar PARAR. Voce pode minimizar o app — '
            'se fechar sem querer, reabra o app para retomar o GPS automaticamente.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          if (permissionIssue != null) ...[
            const SizedBox(height: 8),
            Text(permissionIssue!, style: const TextStyle(color: AppColors.statusStopped, fontSize: 12)),
            TextButton(onPressed: onOpenSettings, child: const Text('Abrir configuracoes')),
          ],
          if (myTrack != null) ...[
            const SizedBox(height: 12),
            VehicleLocationMapPreview.live(track: myTrack!),
          ],
        ],
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle, required this.user, required this.ref});

  final Vehicle vehicle;
  final AppUser? user;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final isMoving = vehicle.status == VehicleStatus.moving;
    final color = isMoving ? AppColors.statusMoving : AppColors.statusStopped;
    final isMine = vehicle.currentDriverId == user?.id && isMoving;
    final alreadyUsingAnother = ref.watch(vehicleControllerProvider).any(
          (item) => item.currentDriverId == user?.id && item.status == VehicleStatus.moving && item.id != vehicle.id,
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isMine ? AppColors.statusMovingBg.withOpacity(0.35) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isMine ? AppColors.statusMoving.withOpacity(0.3) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  vehicle.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                vehicle.plate,
                style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(vehicle.model, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: color),
              const SizedBox(width: 8),
              Text(
                isMoving ? 'EM MOVIMENTO' : 'PARADO',
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FleetInfoRow(
            icon: Icons.person_outline,
            label: 'Motorista',
            value: vehicle.currentDriverName ?? 'Nenhum',
          ),
          if (vehicle.hasMaintenancePlan) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _openMaintenancePlan(context),
              icon: const Icon(Icons.build_circle_outlined),
              label: const Text('Ver plano de manutencao'),
            ),
          ],
          if (isMoving)
            FleetInfoRow(icon: Icons.access_time, label: 'Inicio', value: formatDateTime(vehicle.startedAt))
          else ...[
            FleetInfoRow(icon: Icons.place_outlined, label: 'Local', value: vehicle.stoppedLocation ?? 'Nao informado'),
            if (vehicle.stoppedAt != null)
              FleetInfoRow(icon: Icons.schedule, label: 'Parado desde', value: formatTime(vehicle.stoppedAt)),
            if (vehicle.hasStoppedCoordinates) ...[
              const SizedBox(height: 12),
              _ParkedVehicleMapSection(vehicle: vehicle),
            ],
          ],
          const SizedBox(height: 14),
          if (isMoving && isMine)
            OutlinedButton.icon(onPressed: () => _stop(context), icon: const Icon(Icons.stop_circle_outlined), label: const Text('PARAR / OFF'))
          else if (!isMoving && !alreadyUsingAnother)
            ElevatedButton.icon(onPressed: () => _confirmStart(context), icon: const Icon(Icons.play_circle_outline), label: const Text('INICIAR / ON'))
          else if (!isMoving && alreadyUsingAnother)
            const Text('Voce ja esta usando outro veiculo.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
          else if (isMoving)
            const Text('Veiculo indisponivel para outro motorista.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _confirmStart(BuildContext context) async {
    final operator = user;
    if (operator == null) return;
    await _confirmStartWithChecklist(context, operator);
  }

  Future<void> _openMaintenancePlan(BuildContext context) async {
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

  Future<void> _confirmStartWithChecklist(BuildContext context, AppUser operator) async {
    var todayChecklist = todayChecklistForVehicle(ref, vehicle.id);

    if (todayChecklist == null) {
      final completed = await VehicleChecklistSheet.show(
        context,
        driver: operator,
        vehicle: vehicle,
      );
      if (completed == null || !context.mounted) return;
      todayChecklist = completed;
    } else {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Checklist ja feito hoje'),
          content: Text(
            'Voce ja concluiu o checklist do ${vehicle.name} hoje.\n\n'
            'Deseja iniciar a corrida ou baixar/compartilhar o PDF?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(context, 'pdf'), child: const Text('Ver PDF')),
            ElevatedButton(onPressed: () => Navigator.pop(context, 'start'), child: const Text('INICIAR / ON')),
          ],
        ),
      );
      if (!context.mounted) return;
      if (action == 'pdf') {
        await showChecklistPdfOptions(context, todayChecklist);
        return;
      }
      if (action != 'start') return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar inicio'),
        content: Text('Deseja iniciar o uso do veiculo ${vehicle.name}?\n\nOperador: ${operator.name}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('INICIAR / ON')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final trackingService = ref.read(locationTrackingServiceProvider);
    final canTrack = await trackingService.canStartTripTracking();
    if (!canTrack && context.mounted) {
      final issue = trackingService.permissionIssue ??
          'Permita localizacao "O tempo todo" e desative economia de bateria para este app.';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('GPS necessario para corrida'),
          content: Text('$issue\n\nSem isso, o rastreamento para se o app for fechado.'),
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
      return;
    }

    final error = await ref.read(vehicleControllerProvider.notifier).start(vehicle.id, operator);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    unawaited(ref.read(tripStartVoiceServiceProvider).announceTripStart(operator.name));
  }

  Future<void> _stop(BuildContext context) async {
    if (!context.mounted) return;

    final detected = await runWithBlockingLoadingDialog<StopLocationSnapshot?>(
      context,
      message: 'Obtendo localizacao atual...',
      action: () => ref
          .read(locationTrackingServiceProvider)
          .resolveCurrentStopLocation()
          .timeout(const Duration(seconds: 12), onTimeout: () => null),
    );

    if (!context.mounted) return;

    final controller = TextEditingController(text: detected?.label ?? '');
    final location = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Veiculo parado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Motorista: ${user!.name}'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Local onde foi deixado',
                helperText: detected == null
                    ? 'Nao foi possivel detectar automaticamente. Informe o local.'
                    : 'Local detectado pelo GPS. Voce pode editar se necessario.',
                prefixIcon: const Icon(Icons.place_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text.trim());
            },
            child: const Text('CONFIRMAR PARADA'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (location == null || !context.mounted) return;

    final distanceKm = ref.read(locationTrackingServiceProvider).consumeSessionDistanceKm();
    final error = await runWithBlockingLoadingDialog<String?>(
      context,
      message: 'Registrando parada...',
      action: () => ref
          .read(vehicleControllerProvider.notifier)
          .stop(
            vehicle.id,
            user!,
            location,
            distanceKm: distanceKm > 0 ? distanceKm : null,
            stoppedLatitude: detected?.latitude,
            stoppedLongitude: detected?.longitude,
          )
          .timeout(const Duration(seconds: 15), onTimeout: () => 'Tempo esgotado ao registrar parada.'),
    );

    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    await ref.read(locationTrackingServiceProvider).endTripSession();
    unawaited(ref.read(tripStartVoiceServiceProvider).announceTripStop());

    if (context.mounted && distanceKm > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Corrida registrada: ${distanceKm.toStringAsFixed(1)} km')),
      );
    }
  }
}

class _ParkedVehicleMapSection extends ConsumerStatefulWidget {
  const _ParkedVehicleMapSection({required this.vehicle});

  final Vehicle vehicle;

  @override
  ConsumerState<_ParkedVehicleMapSection> createState() => _ParkedVehicleMapSectionState();
}

class _ParkedVehicleMapSectionState extends ConsumerState<_ParkedVehicleMapSection> {
  final _distance = const Distance();
  LatLng? _myPosition;
  var _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_refreshDistance()));
  }

  Future<void> _refreshDistance() async {
    if (_loading) return;
    setState(() => _loading = true);
    final snapshot = await ref.read(locationTrackingServiceProvider).getCurrentCoordinates();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _myPosition = snapshot == null ? null : LatLng(snapshot.latitude, snapshot.longitude);
    });
  }

  String? _distanceLabel() {
    if (_myPosition == null || !widget.vehicle.hasStoppedCoordinates) return null;
    final km = _distance.as(
      LengthUnit.Kilometer,
      _myPosition!,
      LatLng(widget.vehicle.stoppedLatitude!, widget.vehicle.stoppedLongitude!),
    );
    if (km < 1) return '${(km * 1000).round()} m de voce';
    return '${km.toStringAsFixed(1)} km de voce';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Ultima localizacao no mapa',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        VehicleLocationMapPreview.parked(
          vehicle: widget.vehicle,
          distanceLabel: _distanceLabel(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _loading ? null : _refreshDistance,
            icon: _loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location, size: 18),
            label: const Text('Calcular distancia ate mim'),
          ),
        ),
      ],
    );
  }
}
