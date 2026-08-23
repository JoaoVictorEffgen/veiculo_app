import 'dart:async';

import 'package:flutter/material.dart';

Future<void> dismissBlockingLoadingDialog(BuildContext context) async {
  await Future<void>.delayed(const Duration(milliseconds: 80));
  if (!context.mounted) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  if (navigator.canPop()) {
    navigator.pop();
  }
}

Future<T> runWithBlockingLoadingDialog<T>(
  BuildContext context, {
  required String message,
  required Future<T> Function() action,
}) async {
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) => PopScope(
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
      ),
    ),
  );

  await Future<void>.delayed(const Duration(milliseconds: 120));

  try {
    return await action();
  } finally {
    await dismissBlockingLoadingDialog(context);
  }
}
