import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../app/theme.dart';
import '../models/app_models.dart';
import 'vehicle_repository.dart';

class AnnouncementNotificationService {
  AnnouncementNotificationService(this._repository);

  final VehicleRepository _repository;
  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  StreamSubscription<List<FleetAnnouncement>>? _subscription;
  StreamSubscription<List<FleetAdminAlert>>? _alertsSubscription;
  StreamSubscription<List<DriverIssueReport>>? _reportsSubscription;
  final Map<String, AnnouncementResponseStatus?> _knownResponses = {};
  final Set<String> _knownAlertIds = {};
  final Set<String> _knownReportIds = {};
  final Map<String, bool> _knownReportReplies = {};
  bool _initialized = false;
  bool _seeded = false;
  bool _alertsSeeded = false;
  bool _reportsSeeded = false;
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
    await _reportsSubscription?.cancel();
    _subscription = null;
    _alertsSubscription = null;
    _reportsSubscription = null;
    _activeUser = user;
    _knownResponses.clear();
    _knownAlertIds.clear();
    _knownReportIds.clear();
    _knownReportReplies.clear();
    _seeded = false;
    _alertsSeeded = false;
    _reportsSeeded = false;

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
      _reportsSubscription = _repository.watchDriverIssueReports(user).listen((reports) {
        _handleDriverReportsForAdmin(reports);
      });
    }

    if (user.role == UserRole.driver) {
      _reportsSubscription = _repository.watchDriverIssueReports(user).listen((reports) {
        _handleDriverReportsForDriver(reports);
      });
    }
  }

  void _handleDriverReportsForAdmin(List<DriverIssueReport> reports) {
    if (!_reportsSeeded) {
      for (final report in reports) {
        _knownReportIds.add(report.id);
      }
      _reportsSeeded = true;
      return;
    }

    for (final report in reports) {
      if (_knownReportIds.contains(report.id)) continue;
      _knownReportIds.add(report.id);

      final vehicleLabel = report.vehicleName == null ? '' : ' • ${report.vehicleName}';
      unawaited(_showNotification(
        title: 'Novo relato de problema',
        body: '${report.driverName}$vehicleLabel: ${report.message}',
        id: report.id.hashCode,
      ));
    }
  }

  void _handleDriverReportsForDriver(List<DriverIssueReport> reports) {
    if (!_reportsSeeded) {
      for (final report in reports) {
        _knownReportIds.add(report.id);
        _knownReportReplies[report.id] = report.hasAdminReply;
      }
      _reportsSeeded = true;
      return;
    }

    for (final report in reports) {
      _knownReportIds.add(report.id);
      final hadReply = _knownReportReplies[report.id] ?? false;
      _knownReportReplies[report.id] = report.hasAdminReply;

      if (!hadReply && report.hasAdminReply) {
        unawaited(_showNotification(
          title: 'Resposta ao seu relato',
          body: report.adminReply!,
          id: '${report.id}_reply'.hashCode,
        ));
      }
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
      final taskLabel = alert.isGroupTask ? 'Tarefa geral' : 'Tarefa';
      final body = alert.isRejected && alert.rejectionReason != null
          ? '${alert.driverName} $statusLabel ($taskLabel): ${alert.message}\nMotivo: ${alert.rejectionReason}'
          : '${alert.driverName} $statusLabel ($taskLabel): ${alert.message}';

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
      title: message.notification?.title ?? AppBranding.appName,
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
    await _reportsSubscription?.cancel();
    _subscription = null;
    _alertsSubscription = null;
    _reportsSubscription = null;
    _activeUser = null;
    _knownResponses.clear();
    _knownAlertIds.clear();
    _knownReportIds.clear();
    _knownReportReplies.clear();
    _seeded = false;
    _alertsSeeded = false;
    _reportsSeeded = false;
  }
}
