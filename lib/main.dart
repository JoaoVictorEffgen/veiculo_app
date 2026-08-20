import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'firebase_options.dart';
import 'shared/services/app_providers.dart';
import 'shared/services/firebase_vehicle_repository.dart';
import 'shared/services/location_tracking_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint(details.toString());
  };

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final repository = FirebaseVehicleRepository();
  final locationTrackingService = LocationTrackingService();

  runApp(
    ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repository),
        authControllerProvider.overrideWith((ref) => AuthController(repository)),
        locationTrackingServiceProvider.overrideWithValue(locationTrackingService),
      ],
      child: const VehicleControlApp(),
    ),
  );

  unawaited(
    repository.ensureSeedData().timeout(const Duration(seconds: 30)).catchError((Object error) {
      debugPrint('Seed Firebase: $error');
    }),
  );
}
