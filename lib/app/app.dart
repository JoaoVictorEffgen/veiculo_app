import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/widgets/announcement_notification_binder.dart';
import '../core/widgets/location_tracking_binder.dart';
import 'router.dart';
import 'theme.dart';

class VehicleControlApp extends ConsumerWidget {
  const VehicleControlApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return AnnouncementNotificationBinder(
      child: LocationTrackingBinder(
        child: MaterialApp.router(
          title: 'Controle de Veículos',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    );
  }
}
