import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../firebase/firestore_paths.dart';
import '../../core/utils/iterable_extensions.dart';
import '../models/app_models.dart';
import 'active_trip_session_service.dart';

abstract final class LocationTrackingConfig {
  static const updateInterval = Duration(seconds: 5);
  static const distanceFilterMeters = 0;
  static const staleAfter = Duration(seconds: 20);
  static const displayMaxAge = Duration(minutes: 3);
  static const displayStaleMaxAge = Duration(hours: 2);
  static const watchdogInterval = Duration(seconds: 10);
  static const minStepMeters = 12;
  static const maxStepMeters = 400;
}

class LocationTrackingService {
  LocationTrackingService({
    FirebaseFirestore? firestore,
    ActiveTripSessionService? sessionService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _sessionService = sessionService ?? ActiveTripSessionService();

  final FirebaseFirestore _firestore;
  final ActiveTripSessionService _sessionService;
  StreamSubscription<Position>? _subscription;
  Timer? _watchdogTimer;
  String? _activeDriverId;
  AppUser? _activeUser;
  Vehicle? _activeVehicle;
  String? _permissionIssue;
  Position? _lastPosition;
  DateTime? _lastPositionAt;
  DateTime? _lastPublishAt;
  double _sessionDistanceMeters = 0;

  bool get isTracking => _subscription != null;
  String? get permissionIssue => _permissionIssue;
  double get sessionDistanceKm => _sessionDistanceMeters / 1000;

  double consumeSessionDistanceKm() {
    final km = double.parse(sessionDistanceKm.toStringAsFixed(2));
    _sessionDistanceMeters = 0;
    return km;
  }

  Future<bool> ensurePermission({bool requireBackground = true, bool blockWithoutAlways = false}) async {
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
            'Para rastrear com o app fechado, escolha "Permitir o tempo todo" nas configuracoes de localizacao.';
        if (blockWithoutAlways) return false;
      }
    }

    if (blockWithoutAlways &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        permission != LocationPermission.always) {
      _permissionIssue =
          'Permita localizacao "O tempo todo" antes de iniciar a corrida. Sem isso o GPS para se o app fechar.';
      return false;
    }

    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }

  Future<void> requestBatteryOptimizationExemption() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) return;
    await Permission.ignoreBatteryOptimizations.request();
  }

  Future<bool> canStartTripTracking() async {
    final granted = await ensurePermission(requireBackground: true, blockWithoutAlways: true);
    if (!granted) return false;
    await requestBatteryOptimizationExemption();
    return true;
  }

  Future<void> syncTracking({
    required AppUser? user,
    required List<Vehicle> vehicles,
    required bool vehiclesLoaded,
  }) async {
    if (user == null) {
      await _sessionService.clear();
      await pauseLocalTracking();
      return;
    }

    if (user.role == UserRole.admin) {
      await pauseLocalTracking();
      return;
    }

    final activeVehicle = vehicles
        .where((vehicle) => vehicle.currentDriverId == user.id && vehicle.status == VehicleStatus.moving)
        .firstOrNull;

    if (activeVehicle != null) {
      await _sessionService.save(driverId: user.id, vehicleId: activeVehicle.id);
      await startTracking(user: user, vehicle: activeVehicle);
      return;
    }

    final session = await _sessionService.read();
    if (session?.driverId == user.id) {
      if (!vehiclesLoaded) {
        if (isTracking) return;
        return;
      }

      await _sessionService.clear();
    }

    await pauseLocalTracking();
  }

  Future<void> endTripSession() async {
    await _sessionService.clear();
    await pauseLocalTracking();
  }

  Future<void> startTracking({required AppUser user, required Vehicle vehicle, bool forceRestart = false}) async {
    if (!forceRestart && _activeDriverId == user.id && _subscription != null) {
      _activeUser = user;
      _activeVehicle = vehicle;
      return;
    }

    await pauseLocalTracking();

    final granted = await ensurePermission(requireBackground: true);
    if (!granted) {
      debugPrint('GPS: permissao de localizacao negada.');
      return;
    }

    _activeDriverId = user.id;
    _activeUser = user;
    _activeVehicle = vehicle;
    _lastPublishAt = null;

    final settings = _buildLocationSettings(vehicleName: vehicle.name);

    _subscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) => unawaited(_publishPosition(position: position)),
      onError: (Object error) {
        debugPrint('GPS stream error: $error');
        unawaited(_restartStream());
      },
      cancelOnError: false,
    );

    _startWatchdog();

    try {
      final current = await Geolocator.getCurrentPosition(locationSettings: settings);
      await _publishPosition(position: current);
    } catch (error) {
      debugPrint('GPS: falha ao obter posicao inicial: $error');
    }
  }

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(LocationTrackingConfig.watchdogInterval, (_) {
      unawaited(_checkStreamHealth());
    });
  }

  Future<void> _checkStreamHealth() async {
    if (_subscription == null || _activeUser == null || _activeVehicle == null) return;

    final lastPublish = _lastPublishAt;
    if (lastPublish != null && DateTime.now().difference(lastPublish) <= LocationTrackingConfig.staleAfter) {
      return;
    }

    debugPrint('GPS: stream sem atualizacao recente, reiniciando...');
    await _restartStream();
  }

  Future<void> _restartStream() async {
    final user = _activeUser;
    final vehicle = _activeVehicle;
    if (user == null || vehicle == null) return;
    await startTracking(user: user, vehicle: vehicle, forceRestart: true);
  }

  /// Interrompe apenas o GPS local. Nao apaga o documento remoto — isso so ocorre no PARAR.
  Future<void> pauseLocalTracking() async {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _activeDriverId = null;
    _activeUser = null;
    _activeVehicle = null;
    _lastPosition = null;
    _lastPositionAt = null;
    _lastPublishAt = null;
  }

  LocationSettings _buildLocationSettings({required String vehicleName}) {
    if (kIsWeb) {
      return WebSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: LocationTrackingConfig.distanceFilterMeters,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: LocationTrackingConfig.distanceFilterMeters,
        intervalDuration: LocationTrackingConfig.updateInterval,
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: 'Corrida em andamento',
          notificationText: 'Rastreando $vehicleName — toque PARAR no app para encerrar',
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
    );
  }

  double _resolveSpeedKmh(Position position) {
    final previous = _lastPosition;
    final previousAt = _lastPositionAt;

    if (previous != null && previousAt != null) {
      final elapsedSeconds = position.timestamp.difference(previousAt).inMilliseconds / 1000.0;
      if (elapsedSeconds > 0) {
        final meters = Geolocator.distanceBetween(
          previous.latitude,
          previous.longitude,
          position.latitude,
          position.longitude,
        );
        final derived = (meters / elapsedSeconds) * 3.6;
        if (derived > 0) return derived;
      }
    }

    if (position.speed >= 0) {
      return position.speed * 3.6;
    }

    return 0;
  }

  Future<void> _publishPosition({required Position position}) async {
    final user = _activeUser;
    final vehicle = _activeVehicle;
    if (user == null || vehicle == null || _activeDriverId != user.id) return;

    final speedKmh = _resolveSpeedKmh(position);
    _accumulateDistance(position);

    try {
      await _firestore.collection(FirestorePaths.tracking).doc(user.id).set({
        'driverId': user.id,
        'driverName': user.name,
        'vehicleId': vehicle.id,
        'vehicleName': vehicle.name,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'speedKmh': double.parse(speedKmh.toStringAsFixed(1)),
        'sessionDistanceKm': double.parse(sessionDistanceKm.toStringAsFixed(2)),
        'accuracy': position.accuracy,
        'heading': position.heading,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _lastPublishAt = DateTime.now();
    } catch (error) {
      debugPrint('GPS: falha ao publicar posicao: $error');
    }

    _lastPosition = position;
    _lastPositionAt = position.timestamp;
  }

  void _accumulateDistance(Position position) {
    final previous = _lastPosition;
    if (previous == null) return;

    final meters = Geolocator.distanceBetween(
      previous.latitude,
      previous.longitude,
      position.latitude,
      position.longitude,
    );

    if (meters >= LocationTrackingConfig.minStepMeters && meters <= LocationTrackingConfig.maxStepMeters) {
      _sessionDistanceMeters += meters;
    }
  }

  Future<void> openPermissionSettings() => Geolocator.openAppSettings();

  Future<String?> resolveCurrentLocationLabel() async {
    try {
      final granted = await ensurePermission(requireBackground: false);
      if (!granted) return null;

      final settings = _buildLocationSettings(vehicleName: _activeVehicle?.name ?? 'Veiculo');
      final position = await Geolocator.getCurrentPosition(locationSettings: settings).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('GPS timeout'),
      );
      return await _formatLocationLabel(position).timeout(
        const Duration(seconds: 8),
        onTimeout: () => '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
      );
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
    unawaited(pauseLocalTracking());
  }
}
