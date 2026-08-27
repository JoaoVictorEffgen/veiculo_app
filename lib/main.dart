import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'firebase_options.dart';
import 'shared/services/app_providers.dart';
import 'shared/services/firebase_vehicle_repository.dart';
import 'shared/services/location_tracking_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint(details.toString());
  };

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  try {
    await FirebaseFirestore.instance.clearPersistence();
  } catch (error) {
    debugPrint('Firestore clearPersistence: $error');
  }
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

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
    Future<void>.delayed(const Duration(seconds: 8), () async {
      if (repository.currentUser != null || repository.hasPersistedAuthSession) return;
      try {
        await repository.ensureSeedData().timeout(const Duration(seconds: 45));
      } catch (error) {
        debugPrint('Seed Firebase: $error');
      }
    }),
  );
}
