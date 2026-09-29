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
  if (kIsWeb) {
    await auth.sendPasswordResetEmail(email: normalizedEmail);
    return;
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
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
    case TargetPlatform.iOS:
      await auth.sendPasswordResetEmail(
        email: normalizedEmail,
        actionCodeSettings: ActionCodeSettings(
          url: firebaseAuthContinueUrl,
          handleCodeInApp: false,
          iOSBundleId: kFirebaseAuthAndroidPackage,
        ),
      );
    default:
      await auth.sendPasswordResetEmail(email: normalizedEmail);
  }
}

String? passwordResetErrorMessage(FirebaseAuthException error) {
  switch (error.code) {
    case 'invalid-email':
      return 'Informe um e-mail valido.';
    case 'too-many-requests':
      return 'Muitas tentativas. Aguarde alguns minutos e tente novamente.';
    case 'user-not-found':
      return 'Nao ha conta com este e-mail. Use o e-mail cadastrado pelo administrador ou contas demo apos abrir o app online.';
    case 'invalid-continue-uri':
    case 'unauthorized-continue-uri':
      return 'Configuracao de recuperacao incompleta no Firebase. Contate o suporte.';
    default:
      return error.message ?? 'Nao foi possivel enviar o e-mail de recuperacao.';
  }
}
