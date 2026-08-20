import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../firebase/firestore_paths.dart';
import '../models/app_models.dart';

abstract final class LocationTrackingConfig {
  static const updateInterval = Duration(seconds: 5);
  static const distanceFilterMeters = 0;
}

class LocationTrackingService {
  LocationTrackingService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  StreamSubscription<Position>? _subscription;
  String? _activeDriverId;
  AppUser? _activeUser;
  Vehicle? _activeVehicle;
  String? _permissionIssue;
  Position? _lastPosition;
  DateTime? _lastPositionAt;

  bool get isTracking => _subscription != null;
  String? get permissionIssue => _permissionIssue;

  Future<bool> ensurePermission({bool requireBackground = true}) async {
    _permissionIssue = null;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _permissionIssue = 'Ative o GPS do celular para registrar a corrida.';
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      _permissionIssue = 'Permissao de localizacao negada.';
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      _permissionIssue = 'Permissao de localizacao bloqueada. Libere nas configuracoes do app.';
      return false;
    }

    if (requireBackground && !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (permission == LocationPermission.whileInUse) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse) {
        _permissionIssue =
            'Para rastrear com o app minimizado, escolha "Permitir o tempo todo" nas configuracoes de localizacao.';
      }
    }

    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
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
    if (_activeDriverId == user.id && _subscription != null) {
      _activeUser = user;
      _activeVehicle = vehicle;
      return;
    }

    await stopTracking();

    final granted = await ensurePermission();
    if (!granted) {
      debugPrint('GPS: permissao de localizacao negada.');
      return;
    }

    _activeDriverId = user.id;
    _activeUser = user;
    _activeVehicle = vehicle;

    final settings = _buildLocationSettings(vehicleName: vehicle.name);

    _subscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) => unawaited(_publishPosition(position: position)),
      onError: (Object error) => debugPrint('GPS stream error: $error'),
    );

    try {
      final current = await Geolocator.getCurrentPosition(locationSettings: settings);
      await _publishPosition(position: current);
    } catch (error) {
      debugPrint('GPS: falha ao obter posicao inicial: $error');
    }
  }

  Future<void> stopTracking() async {
    await _subscription?.cancel();
    _subscription = null;

    final driverId = _activeDriverId;
    _activeDriverId = null;
    _activeUser = null;
    _activeVehicle = null;
    _lastPosition = null;
    _lastPositionAt = null;

    if (driverId == null) return;

    try {
      await _firestore.collection(FirestorePaths.tracking).doc(driverId).delete();
    } catch (error) {
      debugPrint('GPS: falha ao remover tracking: $error');
    }
  }

  LocationSettings _buildLocationSettings({required String vehicleName}) {
    if (kIsWeb) {
      return WebSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: LocationTrackingConfig.distanceFilterMeters,
        timeLimit: LocationTrackingConfig.updateInterval,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: LocationTrackingConfig.distanceFilterMeters,
        intervalDuration: LocationTrackingConfig.updateInterval,
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'Corrida em andamento',
          notificationText: 'Rastreando $vehicleName em segundo plano',
          notificationChannelName: 'Rastreamento da frota',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.automotiveNavigation,
        distanceFilter: LocationTrackingConfig.distanceFilterMeters,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }

    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: LocationTrackingConfig.distanceFilterMeters,
      timeLimit: LocationTrackingConfig.updateInterval,
    );
  }

  double _resolveSpeedKmh(Position position) {
    if (position.speed >= 0) {
      return position.speed * 3.6;
    }

    final previous = _lastPosition;
    final previousAt = _lastPositionAt;
    if (previous == null || previousAt == null) return 0;

    final elapsedSeconds = position.timestamp.difference(previousAt).inMilliseconds / 1000.0;
    if (elapsedSeconds <= 0) return 0;

    final meters = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      position.latitude,
      position.longitude,
    );

    return (meters / elapsedSeconds) * 3.6;
  }

  Future<void> _publishPosition({required Position position}) async {
    final user = _activeUser;
    final vehicle = _activeVehicle;
    if (user == null || vehicle == null || _activeDriverId != user.id) return;

    final speedKmh = _resolveSpeedKmh(position);

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

    _lastPosition = position;
    _lastPositionAt = position.timestamp;
  }

  Future<void> openPermissionSettings() => Geolocator.openAppSettings();

  Future<String?> resolveCurrentLocationLabel() async {
    try {
      final granted = await ensurePermission(requireBackground: false);
      if (!granted) return null;

      final settings = _buildLocationSettings(vehicleName: _activeVehicle?.name ?? 'Veiculo');
      final position = await Geolocator.getCurrentPosition(locationSettings: settings);
      return await _formatLocationLabel(position);
    } catch (error) {
      debugPrint('GPS: falha ao obter localizacao atual: $error');
      return null;
    }
  }

  Future<String> _formatLocationLabel(Position position) async {
    try {
      final places = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (places.isNotEmpty) {
        final place = places.first;
        final parts = <String>[
          if (place.street != null && place.street!.trim().isNotEmpty) place.street!.trim(),
          if (place.subLocality != null && place.subLocality!.trim().isNotEmpty) place.subLocality!.trim(),
          if (place.locality != null && place.locality!.trim().isNotEmpty) place.locality!.trim(),
        ];
        if (parts.isNotEmpty) return parts.join(', ');
      }
    } catch (error) {
      debugPrint('GPS: reverse geocoding indisponivel: $error');
    }

    return '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
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
