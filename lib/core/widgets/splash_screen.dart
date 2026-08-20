import 'package:flutter/material.dart';

import 'corporate_ui.dart';

/// Splash inicial — o router redireciona automaticamente conforme a sessao salva.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const CorporateSplash();
}
