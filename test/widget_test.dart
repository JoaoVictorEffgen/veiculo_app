import 'package:drift/native.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vehicle_control_app/app/app.dart';
import 'package:vehicle_control_app/firebase_options.dart';
import 'package:vehicle_control_app/shared/database/app_database.dart';
import 'package:vehicle_control_app/shared/services/app_providers.dart';
import 'package:vehicle_control_app/shared/services/local_vehicle_repository.dart';
import 'package:vehicle_control_app/shared/services/local_vehicle_repository_adapter.dart';
import 'package:vehicle_control_app/shared/services/location_tracking_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } on FirebaseException catch (error) {
      if (error.code != 'duplicate-app') rethrow;
    }
  });

  testWidgets('opens the vehicle control login', (WidgetTester tester) async {
    final local = await LocalVehicleRepository.create(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
    await local.clearSession();
    final repository = LocalVehicleRepositoryAdapter(local);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repository),
          authControllerProvider.overrideWith((ref) => AuthController(repository)),
          locationTrackingServiceProvider.overrideWithValue(LocationTrackingService()),
        ],
        child: const VehicleControlApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('Entrar'), findsOneWidget);
  });
}
