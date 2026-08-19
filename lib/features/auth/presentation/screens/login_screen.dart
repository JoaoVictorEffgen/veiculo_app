import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/app_providers.dart';

/// Tela de login — implementação completa na Etapa 2
/// (integração com Firebase Auth + identificação automática do motorista).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() {
    setState(() => _loading = true);
    final error = ref.read(authControllerProvider.notifier).login(_emailController.text, _passwordController.text);
    setState(() => _loading = false);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final user = ref.read(authControllerProvider);
    context.go(user?.role == UserRole.admin ? AppRoutes.admin : AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.local_shipping_rounded, size: 72),
                  const SizedBox(height: 20),
                  Text('Controle de Veículos', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text('Entre com seu usuário corporativo', textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.person_outline))),
                  const SizedBox(height: 12),
                  TextField(controller: _passwordController, obscureText: true, onSubmitted: (_) => _login(), decoration: const InputDecoration(labelText: 'Senha', prefixIcon: Icon(Icons.lock_outline))),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(onPressed: _loading ? null : _login, icon: const Icon(Icons.login), label: Text(_loading ? 'Entrando...' : 'Entrar')),
                  const SizedBox(height: 20),
                  const Text('MVP local: motorista1@empresa.com a motorista4@empresa.com ou admin@empresa.com. Senha: 123456.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
