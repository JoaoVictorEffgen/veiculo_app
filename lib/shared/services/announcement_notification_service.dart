import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/app_models.dart';
import 'vehicle_repository.dart';

class AnnouncementNotificationService {
  AnnouncementNotificationService(this._repository);

  final VehicleRepository _repository;
  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  StreamSubscription<List<FleetAnnouncement>>? _subscription;
  StreamSubscription<List<FleetAdminAlert>>? _alertsSubscription;
  final Map<String, AnnouncementResponseStatus?> _knownResponses = {};
  final Set<String> _knownAlertIds = {};
  bool _initialized = false;
  bool _seeded = false;
  bool _alertsSeeded = false;
  AppUser? _activeUser;

  static const _channelId = 'fleet_announcements';
  static const _channelName = 'Tarefas da frota';

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (!kIsWeb) {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      await _localNotifications.initialize(initSettings);

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              importance: Importance.high,
            ),
          );

      await _messaging.requestPermission(alert: true, badge: true, sound: true);
      FirebaseMessaging.onMessage.listen(_onForegroundPush);
      FirebaseMessaging.onMessageOpenedApp.listen(_onOpenedFromPush);
    }
  }

  Future<void> bindUser(AppUser? user) async {
    await _subscription?.cancel();
    await _alertsSubscription?.cancel();
    _subscription = null;
    _alertsSubscription = null;
    _activeUser = user;
    _knownResponses.clear();
    _knownAlertIds.clear();
    _seeded = false;
    _alertsSeeded = false;

    if (user == null) return;

    await initialize();

    if (!kIsWeb) {
      final token = await _messaging.getToken();
      if (token != null) {
        await _repository.saveFcmToken(user, token);
      }
      _messaging.onTokenRefresh.listen((token) async {
        final current = _activeUser;
        if (current != null) {
          await _repository.saveFcmToken(current, token);
        }
      });
    }

    _subscription = _repository.watchAnnouncementsForUser(user).listen((announcements) {
      _handleAnnouncements(user, announcements);
    });

    if (user.role == UserRole.admin) {
      _alertsSubscription = _repository.watchAdminAlerts().listen((alerts) {
        _handleAdminAlerts(alerts);
      });
    }
  }

  void _handleAdminAlerts(List<FleetAdminAlert> alerts) {
    if (!_alertsSeeded) {
      for (final alert in alerts) {
        _knownAlertIds.add(alert.id);
      }
      _alertsSeeded = true;
      return;
    }

    for (final alert in alerts) {
      if (_knownAlertIds.contains(alert.id)) continue;
      _knownAlertIds.add(alert.id);

      final statusLabel = alert.responseStatus == AnnouncementResponseStatus.completed ? 'concluiu' : 'recusou';
      final body = alert.isRejected && alert.rejectionReason != null
          ? '${alert.driverName} $statusLabel: ${alert.message}\nMotivo: ${alert.rejectionReason}'
          : '${alert.driverName} $statusLabel: ${alert.message}';

      unawaited(_showNotification(
        title: 'Resposta da tarefa',
        body: body,
        id: alert.id.hashCode,
      ));
    }
  }

  void _handleAnnouncements(AppUser user, List<FleetAnnouncement> announcements) {
    if (!_seeded) {
      for (final announcement in announcements) {
        _knownResponses[announcement.id] = announcement.responseStatus;
      }
      _seeded = true;

      if (user.role == UserRole.driver) {
        return;
      }
      return;
    }

    if (user.role == UserRole.driver) {
      for (final announcement in announcements) {
        if (_knownResponses.containsKey(announcement.id)) continue;
        _knownResponses[announcement.id] = announcement.responseStatus;
        if (announcement.targetDriverId == user.id || announcement.targetDriverId == null) {
          unawaited(_showNotification(
            title: 'Nova tarefa da administracao',
            body: announcement.message,
            id: announcement.id.hashCode,
          ));
        }
      }
      return;
    }

    if (user.role == UserRole.admin) {
      for (final announcement in announcements) {
        final previous = _knownResponses[announcement.id];
        _knownResponses[announcement.id] = announcement.responseStatus;

        if (previous != null || announcement.responseStatus == null) continue;
        if (!announcement.requiresResponse) continue;

        final driverName = announcement.respondedByName ?? announcement.targetDriverName ?? 'Motorista';
        final statusLabel =
            announcement.responseStatus == AnnouncementResponseStatus.completed ? 'concluiu' : 'recusou';
        unawaited(_showNotification(
          title: 'Resposta da tarefa',
          body: '$driverName $statusLabel: ${announcement.message}',
          id: '${announcement.id}_${announcement.responseStatus!.name}'.hashCode,
        ));
      }
    }
  }

  Future<void> _showNotification({
    required String title,
    required String body,
    required int id,
  }) async {
    if (kIsWeb) return;

    await _localNotifications.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  void _onForegroundPush(RemoteMessage message) {
    final body = message.notification?.body ?? message.data['message'];
    if (body == null || body.isEmpty) return;
    unawaited(_showNotification(
      title: message.notification?.title ?? 'Controle de Veiculos',
      body: body,
      id: message.hashCode,
    ));
  }

  void _onOpenedFromPush(RemoteMessage message) {
    debugPrint('Notificacao aberta: ${message.data}');
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _alertsSubscription?.cancel();
    _subscription = null;
    _alertsSubscription = null;
    _activeUser = null;
    _knownResponses.clear();
    _knownAlertIds.clear();
    _seeded = false;
    _alertsSeeded = false;
  }
}
