import 'package:shared_preferences/shared_preferences.dart';

class ActiveTripSession {
  const ActiveTripSession({required this.driverId, required this.vehicleId});

  final String driverId;
  final String vehicleId;
}

/// Persiste corrida ativa localmente para retomar GPS apos fechar/reabrir o app.
class ActiveTripSessionService {
  static const _driverKey = 'active_trip_driver_id';
  static const _vehicleKey = 'active_trip_vehicle_id';

  Future<void> save({required String driverId, required String vehicleId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_driverKey, driverId);
    await prefs.setString(_vehicleKey, vehicleId);
  }

  Future<ActiveTripSession?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final driverId = prefs.getString(_driverKey);
    final vehicleId = prefs.getString(_vehicleKey);
    if (driverId == null || vehicleId == null || driverId.isEmpty || vehicleId.isEmpty) {
      return null;
    }
    return ActiveTripSession(driverId: driverId, vehicleId: vehicleId);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_driverKey);
    await prefs.remove(_vehicleKey);
  }
}
