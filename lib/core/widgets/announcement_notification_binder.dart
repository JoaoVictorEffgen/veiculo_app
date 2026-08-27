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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (_, __) => _sync());
    return widget.child;
  }

  Future<void> _sync() async {
    final user = ref.read(authControllerProvider).user;
    await ref.read(announcementNotificationServiceProvider).bindUser(user);
  }
}
