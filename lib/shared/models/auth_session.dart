import 'app_models.dart';

class AuthSession {
  const AuthSession({required this.isReady, this.user});

  const AuthSession.loading() : this(isReady: false);

  const AuthSession.ready(AppUser? user) : this(isReady: true, user: user);

  final bool isReady;
  final AppUser? user;
}
