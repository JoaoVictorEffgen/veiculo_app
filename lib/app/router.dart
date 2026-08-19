import 'package:go_router/go_router.dart';

import '../core/widgets/splash_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/vehicles/presentation/screens/dashboard_screen.dart';
import '../features/history/presentation/screens/history_screen.dart';
import '../features/admin/presentation/screens/admin_screen.dart';

/// Nomes de rota centralizados — evita strings soltas espalhadas pelo app.
class AppRoutes {
  AppRoutes._();

  static const splash = '/';
  static const login = '/login';
  static const dashboard = '/dashboard';
  static const history = '/history';
  static const admin = '/admin';
}

/// Router raiz.
///
/// A partir da Etapa 2, este router receberá um `redirect` que:
/// - manda usuário não autenticado para /login
/// - manda motorista para /dashboard
/// - manda admin para /admin
/// - impede motorista de acessar rotas /admin/*
final appRouter = GoRouter(
  initialLocation: AppRoutes.login,
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: AppRoutes.dashboard,
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: AppRoutes.history,
      builder: (context, state) => const HistoryScreen(),
    ),
    GoRoute(
      path: AppRoutes.admin,
      builder: (context, state) => const AdminScreen(),
    ),
  ],
);
