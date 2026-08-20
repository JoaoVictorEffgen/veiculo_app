import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../shared/models/app_models.dart';
import '../../shared/services/app_providers.dart';
import 'corporate_ui.dart';
import 'main_app_shell.dart';

class AdminOnlyGate extends ConsumerWidget {
  const AdminOnlyGate({super.key, required this.child, this.title = 'Acesso negado'});

  final Widget child;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    if (user?.role != UserRole.admin) {
      return Scaffold(
        appBar: CorporateAppBar(title: title),
        body: Center(
          child: CorporateSurface(
            margin: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48, color: AppColors.primary),
                const SizedBox(height: 12),
                const Text(
                  'Esta area e exclusiva para administradores.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: () => context.go(AppRoutes.dashboard), child: const Text('Voltar')),
              ],
            ),
          ),
        ),
      );
    }
    return child;
  }
}
