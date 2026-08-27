import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/announcement_notification_service.dart';
import '../../shared/services/app_providers.dart';

final announcementNotificationServiceProvider = Provider<AnnouncementNotificationService>((ref) {
  final service = AnnouncementNotificationService(ref.watch(repositoryProvider));
  ref.onDispose(service.dispose);
  return service;
});

class AnnouncementNotificationBinder extends ConsumerStatefulWidget {
  const AnnouncementNotificationBinder({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AnnouncementNotificationBinder> createState() => _AnnouncementNotificationBinderState();
}

class _AnnouncementNotificationBinderState extends ConsumerState<AnnouncementNotificationBinder> {
  Timer? _syncDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleSync());
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, __) => _scheduleSync());
    return widget.child;
  }

  void _scheduleSync() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_sync());
    });
  }

  Future<void> _sync() async {
    final user = ref.read(authControllerProvider).user;
    await ref.read(announcementNotificationServiceProvider).bindUser(user);
  }
}
