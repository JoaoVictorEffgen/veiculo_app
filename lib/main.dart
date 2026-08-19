import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// import 'package:firebase_core/firebase_core.dart';
// import 'config/firebase_options.dart'; // gerado pelo `flutterfire configure` (Etapa 2)

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A inicialização do Firebase será ligada na Etapa 2, junto com a
  // autenticação. Deixamos o app rodando sem Firebase por enquanto para
  // validar a estrutura, tema e navegação base.
  //
  // await Firebase.initializeApp(
  //   options: DefaultFirebaseOptions.currentPlatform,
  // );

  runApp(
    const ProviderScope(
      child: VehicleControlApp(),
    ),
  );
}
