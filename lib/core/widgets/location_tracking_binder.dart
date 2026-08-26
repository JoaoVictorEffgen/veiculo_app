import 'dart:async';

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

class _LocationTrackingBinderState extends ConsumerState<LocationTrackingBinder> with WidgetsBindingObserver {
  var _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ref.read(locationTrackingServiceProvider).pauseLocalTracking());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _sync();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, __) => _sync());
    ref.listen(vehicleControllerProvider, (_, __) => _sync());
    return widget.child;
  }

  Future<void> _sync() async {
    if (!mounted || _syncing) return;
    _syncing = true;
    try {
      final session = ref.read(authControllerProvider);
      if (!session.isReady) return;

      await ref.read(locationTrackingServiceProvider).syncTracking(
            user: session.user,
            vehicles: ref.read(vehicleControllerProvider),
            vehiclesLoaded: ref.read(vehicleControllerProvider.notifier).hasLoaded,
          );
    } finally {
      _syncing = false;
    }
  }
}
