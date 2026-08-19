import 'package:flutter/material.dart';

import 'router.dart';
import 'theme.dart';

class VehicleControlApp extends StatelessWidget {
  const VehicleControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Controle de Veículos',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: appRouter,
    );
  }
}
