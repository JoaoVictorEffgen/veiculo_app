import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/theme.dart';
import '../../core/utils/iterable_extensions.dart';
import '../../shared/models/app_models.dart';
import '../../shared/models/navigation_route.dart';
import '../../shared/services/app_providers.dart';
import '../../shared/services/routing_service.dart';
import 'corporate_ui.dart';
import 'navigation_route_screen.dart';

List<FleetAnnouncement> routableTasksForUser(List<FleetAnnouncement> announcements, AppUser user) {
  return announcements
      .where(
        (announcement) =>
            announcement.isVisibleTo(user) && (announcement.destinationAddress?.trim().isNotEmpty ?? false),
      )
      .toList();
}

Future<ResolvedAddress?> resolveTaskDestination(WidgetRef ref, FleetAnnouncement task) async {
  final address = task.destinationAddress?.trim();
  if (address == null || address.isEmpty) return null;

  if (task.destinationLatitude != null && task.destinationLongitude != null) {
    return ResolvedAddress(
      label: address,
      latitude: task.destinationLatitude!,
      longitude: task.destinationLongitude!,
    );
  }

  return ref.read(geocodingServiceProvider).resolveAddress(address);
}

class DriverRoutePlannerCard extends ConsumerStatefulWidget {
  const DriverRoutePlannerCard({super.key});

  @override
  ConsumerState<DriverRoutePlannerCard> createState() => _DriverRoutePlannerCardState();
}

class _DriverRoutePlannerCardState extends ConsumerState<DriverRoutePlannerCard> {
  static const _customDestinationId = '__custom__';

  final _addressController = TextEditingController();
  var _loading = false;
  String? _selectedDestinationId;

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  String _effectiveSelectionId(List<FleetAnnouncement> tasks) {
    if (_selectedDestinationId == _customDestinationId) return _customDestinationId;
    if (_selectedDestinationId != null && tasks.any((task) => task.id == _selectedDestinationId)) {
      return _selectedDestinationId!;
    }
    if (tasks.length == 1) return tasks.first.id;
    return _customDestinationId;
  }

  bool get _usingCustomDestination => _selectedDestinationId == _customDestinationId;

  void _applySelection(String selectionId, List<FleetAnnouncement> tasks) {
    _selectedDestinationId = selectionId;
    if (selectionId == _customDestinationId) return;
    final task = tasks.where((item) => item.id == selectionId).firstOrNull;
    if (task != null) {
      _addressController.text = task.destinationAddress ?? '';
    }
  }

  FleetAnnouncement? _taskById(List<FleetAnnouncement> tasks, String? id) {
    if (id == null || id == _customDestinationId) return null;
    return tasks.where((task) => task.id == id).firstOrNull;
  }

  String _taskLabel(FleetAnnouncement task) {
    final message = task.message.trim();
    if (message.isEmpty) return task.destinationAddress ?? 'Tarefa';
    if (message.length <= 40) return message;
    return '${message.substring(0, 40)}...';
  }

  Future<FleetAnnouncement?> _pickTask(List<FleetAnnouncement> tasks) async {
    return showDialog<FleetAnnouncement>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selecione a tarefa'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final task = tasks[index];
              return ListTile(
                title: Text(_taskLabel(task)),
                subtitle: Text(
                  task.destinationAddress ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, task),
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

  Future<void> _traceRoute() async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    final tasks = routableTasksForUser(
      ref.read(fleetAnnouncementsProvider).valueOrNull ?? const [],
      user,
    );
    final selectionId = _effectiveSelectionId(tasks);
    var selectedTask = _taskById(tasks, selectionId);
    final address = _addressController.text.trim();

    if (selectedTask == null && address.isEmpty && tasks.length == 1 && !_usingCustomDestination) {
      selectedTask = tasks.first;
    }

    if (selectedTask == null && address.isEmpty && tasks.length > 1) {
      selectedTask = await _pickTask(tasks);
      if (selectedTask == null) return;
    }

    if (selectedTask == null && address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione uma tarefa ou informe o endereco de destino.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final locationService = ref.read(locationTrackingServiceProvider);
      final allowed = await locationService.ensurePermission(requireBackground: false);
      if (!allowed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(locationService.permissionIssue ?? 'Ative o GPS para calcular a rota.')),
        );
        return;
      }

      final coordinates = await locationService.getCurrentCoordinates();
      if (coordinates == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nao foi possivel obter sua localizacao atual.')),
        );
        return;
      }

      final ResolvedAddress destination;
      if (selectedTask != null) {
        final resolved = await resolveTaskDestination(ref, selectedTask);
        if (resolved == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nao foi possivel localizar o endereco da tarefa.')),
          );
          return;
        }
        destination = resolved;
      } else {
        final resolved = await ref.read(geocodingServiceProvider).resolveAddress(address);
        if (resolved == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Endereco nao encontrado. Tente ser mais especifico.')),
          );
          return;
        }
        destination = resolved;
      }

      final route = await ref.read(routingServiceProvider).buildDrivingRoute(
            origin: LatLng(coordinates.latitude, coordinates.longitude),
            destination: destination,
          );

      if (!mounted) return;
      await openNavigationRouteScreen(context, route: route);
    } on RoutingException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao calcular rota: $error')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    if (user == null) return const SizedBox.shrink();

    final announcements = ref.watch(fleetAnnouncementsProvider).valueOrNull ?? const <FleetAnnouncement>[];
    final tasksWithRoute = routableTasksForUser(announcements, user);
    final selectionId = _effectiveSelectionId(tasksWithRoute);
    final usingTask = selectionId != _customDestinationId;

    if (usingTask && _addressController.text.isEmpty) {
      final task = _taskById(tasksWithRoute, selectionId);
      if (task != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_addressController.text.isEmpty) {
            _addressController.text = task.destinationAddress ?? '';
          }
        });
      }
    }

    final subtitle = tasksWithRoute.isEmpty
        ? 'Digite um endereco para calcular a rota a partir da sua posicao atual.'
        : tasksWithRoute.length == 1
            ? 'A tarefa com endereco sera usada automaticamente. Voce tambem pode informar outro destino.'
            : 'Selecione uma tarefa com destino ou informe outro endereco.';

    return CorporateSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CorporateSectionTitle(title: 'Minha rota'),
          Text(
            subtitle,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          if (tasksWithRoute.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selectionId,
              decoration: const InputDecoration(
                labelText: 'Destino',
                prefixIcon: Icon(Icons.task_alt_outlined),
              ),
              items: [
                ...tasksWithRoute.map(
                  (task) => DropdownMenuItem(
                    value: task.id,
                    child: Text(_taskLabel(task), overflow: TextOverflow.ellipsis),
                  ),
                ),
                const DropdownMenuItem(
                  value: _customDestinationId,
                  child: Text('Outro endereco'),
                ),
              ],
              onChanged: _loading
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        if (value == _customDestinationId) {
                          _selectedDestinationId = _customDestinationId;
                          _addressController.clear();
                        } else {
                          _applySelection(value, tasksWithRoute);
                        }
                      });
                    },
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            enabled: !_loading && !usingTask,
            readOnly: usingTask,
            autofocus: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _traceRoute(),
            decoration: InputDecoration(
              labelText: usingTask ? 'Endereco da tarefa selecionada' : 'Endereco de destino',
              hintText: usingTask ? null : 'Ex.: Av. Paulista, 1000, Sao Paulo',
              prefixIcon: const Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _loading ? null : _traceRoute,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.route_outlined),
            label: Text(_loading ? 'CALCULANDO...' : 'TRACAR ROTA'),
          ),
        ],
      ),
    );
  }
}

Future<void> openRouteToDestination(
  BuildContext context,
  WidgetRef ref, {
  required String destinationAddress,
  required double? destinationLatitude,
  required double? destinationLongitude,
}) async {
  final task = FleetAnnouncement(
    id: 'manual',
    message: '',
    createdAt: DateTime.now(),
    createdByName: '',
    destinationAddress: destinationAddress,
    destinationLatitude: destinationLatitude,
    destinationLongitude: destinationLongitude,
  );

  final destination = await resolveTaskDestination(ref, task);
  if (destination == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nao foi possivel localizar o endereco.')),
    );
    return;
  }

  final locationService = ref.read(locationTrackingServiceProvider);
  final allowed = await locationService.ensurePermission(requireBackground: false);
  if (!allowed) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(locationService.permissionIssue ?? 'Ative o GPS para calcular a rota.')),
    );
    return;
  }

  final coordinates = await locationService.getCurrentCoordinates();
  if (coordinates == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nao foi possivel obter sua localizacao atual.')),
    );
    return;
  }

  try {
    final route = await ref.read(routingServiceProvider).buildDrivingRoute(
          origin: LatLng(coordinates.latitude, coordinates.longitude),
          destination: destination,
        );
    if (!context.mounted) return;
    await openNavigationRouteScreen(context, route: route);
  } on RoutingException catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
  }
}
