import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Exibe um dialogo bloqueante, executa [action] e garante fechamento mesmo se
/// o [context] de quem abriu for descartado durante a operacao (ex.: rebuild
/// da lista de veiculos ao parar corrida).
Future<T> runWithBlockingLoadingDialog<T>(
  BuildContext context, {
  required String message,
  required Future<T> Function() action,
}) async {
  if (!context.mounted) {
    return action();
  }

  BuildContext? dialogContext;

  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        dialogContext = ctx;
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Expanded(child: Text(message)),
              ],
            ),
          ),
        );
      },
    ),
  );

  await Future<void>.delayed(Duration.zero);
  await SchedulerBinding.instance.endOfFrame;

  try {
    return await action();
  } finally {
    await _dismissLoadingDialog(dialogContext);
  }
}

Future<void> _dismissLoadingDialog(BuildContext? dialogContext) async {
  await Future<void>.delayed(const Duration(milliseconds: 50));

  final ctx = dialogContext;
  if (ctx == null || !ctx.mounted) return;

  final navigator = Navigator.of(ctx, rootNavigator: true);
  if (navigator.canPop()) {
    navigator.pop();
  }
}
