import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../shared/services/app_providers.dart';

Future<void> showChangeLoginEmailDialog(BuildContext context, WidgetRef ref) async {
  final user = ref.read(authControllerProvider).user;
  if (user == null) return;

  final controller = TextEditingController(text: user.email);
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Alterar e-mail de login'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Informe o novo e-mail. Enviaremos um link de confirmacao para ele. '
            'Depois de confirmar, use esse e-mail para entrar e para recuperar a senha.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4, fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [],
            decoration: const InputDecoration(
              labelText: 'Novo e-mail',
              prefixIcon: Icon(Icons.mail_outline),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () {
            final email = controller.text.trim();
            if (email.isEmpty || !email.contains('@')) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Informe um e-mail valido.')),
              );
              return;
            }
            Navigator.pop(context, true);
          },
          child: const Text('Enviar confirmacao'),
        ),
      ],
    ),
  );

  final newEmail = controller.text.trim().toLowerCase();
  controller.dispose();
  if (submitted != true || !context.mounted) return;

  final error = await ref.read(authControllerProvider.notifier).requestLoginEmailChange(newEmail);
  if (!context.mounted) return;

  if (error != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Enviamos um link para $newEmail. Abra o e-mail, confirme a troca e depois faca login com o novo endereco.',
      ),
    ),
  );
}
