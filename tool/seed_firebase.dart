import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:vehicle_control_app/firebase_options.dart';
import 'package:vehicle_control_app/shared/services/firebase_vehicle_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final repository = FirebaseVehicleRepository();
  await repository.ensureSeedData();
  debugPrint('Seed Firebase concluido.');
}
