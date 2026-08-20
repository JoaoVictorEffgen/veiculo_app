import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vehicle_control_app/shared/services/app_providers.dart';

/// Ativa o GPS automaticamente quando o motorista esta com veiculo em movimento.
class LocationTrackingBinder extends ConsumerStatefulWidget {
  const LocationTrackingBinder({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LocationTrackingBinder> createState() => _LocationTrackingBinderState();
}

class _LocationTrackingBinderState extends ConsumerState<LocationTrackingBinder> {
  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, __) => _sync());
    ref.listen(vehicleControllerProvider, (_, __) => _sync());
    return widget.child;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  Future<void> _sync() async {
    final session = ref.read(authControllerProvider);
    if (!session.isReady) return;

    await ref.read(locationTrackingServiceProvider).syncTracking(
          user: session.user,
          vehicles: ref.read(vehicleControllerProvider),
        );
  }
}
