import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../firebase/firestore_paths.dart';
import '../models/app_models.dart';

class LocationTrackingService {
  LocationTrackingService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  StreamSubscription<Position>? _subscription;
  String? _activeDriverId;

  Future<bool> ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  Future<void> syncTracking({required AppUser? user, required List<Vehicle> vehicles}) async {
    if (user == null || user.role == UserRole.admin) {
      await stopTracking();
      return;
    }

    final activeVehicle = vehicles
        .where((vehicle) => vehicle.currentDriverId == user.id && vehicle.status == VehicleStatus.moving)
        .firstOrNull;

    if (activeVehicle == null) {
      await stopTracking();
      return;
    }

    await startTracking(user: user, vehicle: activeVehicle);
  }

  Future<void> startTracking({required AppUser user, required Vehicle vehicle}) async {
    if (_activeDriverId == user.id && _subscription != null) return;

    await stopTracking();

    final granted = await ensurePermission();
    if (!granted) {
      debugPrint('GPS: permissao de localizacao negada.');
      return;
    }

    _activeDriverId = user.id;

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
    );

    _subscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) => _publishPosition(user: user, vehicle: vehicle, position: position),
      onError: (Object error) => debugPrint('GPS stream error: $error'),
    );

    final current = await Geolocator.getCurrentPosition();
    await _publishPosition(user: user, vehicle: vehicle, position: current);
  }

  Future<void> stopTracking() async {
    await _subscription?.cancel();
    _subscription = null;

    final driverId = _activeDriverId;
    _activeDriverId = null;
    if (driverId == null) return;

    try {
      await _firestore.collection(FirestorePaths.tracking).doc(driverId).delete();
    } catch (error) {
      debugPrint('GPS: falha ao remover tracking: $error');
    }
  }

  Future<void> _publishPosition({
    required AppUser user,
    required Vehicle vehicle,
    required Position position,
  }) async {
    if (_activeDriverId != user.id) return;

    final speedKmh = position.speed >= 0 ? position.speed * 3.6 : 0.0;

    await _firestore.collection(FirestorePaths.tracking).doc(user.id).set({
      'driverId': user.id,
      'driverName': user.name,
      'vehicleId': vehicle.id,
      'vehicleName': vehicle.name,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'speedKmh': double.parse(speedKmh.toStringAsFixed(1)),
      'accuracy': position.accuracy,
      'heading': position.heading,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  void dispose() {
    unawaited(stopTracking());
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
