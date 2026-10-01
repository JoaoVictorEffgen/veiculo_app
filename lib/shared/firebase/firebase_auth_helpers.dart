import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';

/// Pacote Android registrado no Firebase (reset de senha / links de acao).
const kFirebaseAuthAndroidPackage = 'com.example.vehicle_control_app';

String get firebaseAuthContinueUrl {
  final options = DefaultFirebaseOptions.currentPlatform;
  final domain = options.authDomain;
  if (domain != null && domain.isNotEmpty) {
    return 'https://$domain';
  }
  return 'https://${options.projectId}.firebaseapp.com';
}

Future<void> sendPasswordResetEmailToAccount(FirebaseAuth auth, String normalizedEmail) async {
  try {
    await auth.sendPasswordResetEmail(email: normalizedEmail);
  } on FirebaseAuthException catch (error) {
    if (error.code != 'invalid-continue-uri' && error.code != 'unauthorized-continue-uri') {
      rethrow;
    }
    if (kIsWeb) rethrow;
    await auth.sendPasswordResetEmail(
      email: normalizedEmail,
      actionCodeSettings: ActionCodeSettings(
        url: firebaseAuthContinueUrl,
        handleCodeInApp: false,
        androidPackageName: kFirebaseAuthAndroidPackage,
        androidInstallApp: true,
        androidMinimumVersion: '21',
      ),
    );
  }
}

String? passwordResetErrorMessage(FirebaseAuthException error) {
  switch (error.code) {
    case 'invalid-email':
      return 'Informe um e-mail valido.';
    case 'too-many-requests':
      return 'Muitas tentativas. Aguarde alguns minutos e tente novamente.';
    case 'user-not-found':
      return 'Nao ha conta com este e-mail no Firebase. Confira se e o mesmo e-mail que o administrador cadastrou (incluindo letras e dominio).';
    case 'invalid-continue-uri':
    case 'unauthorized-continue-uri':
      return 'Configuracao de recuperacao incompleta no Firebase. Contate o suporte.';
    default:
      return error.message ?? 'Nao foi possivel enviar o e-mail de recuperacao.';
  }
}
