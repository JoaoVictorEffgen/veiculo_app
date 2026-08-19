import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'shared/services/app_providers.dart';
import 'shared/services/local_vehicle_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final repository = await LocalVehicleRepository.create();
  final initialUser = await repository.restoreSession();

  runApp(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith((ref) => AuthController(repository, initialUser: initialUser)),
      ],
      child: const VehicleControlApp(),
    ),
  );
}
