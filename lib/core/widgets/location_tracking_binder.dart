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
  Timer? _syncDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleSync());
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, __) => _scheduleSync());
    ref.listen(vehicleControllerProvider, (_, __) => _scheduleSync());
    return widget.child;
  }

  void _scheduleSync() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_sync());
    });
  }

  Future<void> _sync() async {
    final session = ref.read(authControllerProvider);
    if (!session.isReady) return;

    await ref.read(locationTrackingServiceProvider).syncTracking(
          user: session.user,
          vehicles: ref.read(vehicleControllerProvider),
          vehiclesLoaded: ref.read(vehicleControllerProvider.notifier).hasLoaded,
        );
  }
}
