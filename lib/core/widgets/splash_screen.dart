import 'package:flutter/material.dart';

/// Splash inicial. Na Etapa 2, esta tela passará a checar o estado de
/// autenticação (Firebase Auth) e redirecionar automaticamente para
/// /login ou /dashboard.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_shipping_rounded, size: 64),
            SizedBox(height: 16),
            Text(
              'Controle de Veículos',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
