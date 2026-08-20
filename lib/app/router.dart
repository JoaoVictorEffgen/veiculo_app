import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/main_app_shell.dart';
import '../core/widgets/splash_screen.dart';
import '../features/admin/presentation/screens/fleet_dashboard_screen.dart';
import '../features/admin/presentation/screens/admin_screen.dart';
import '../features/admin/presentation/screens/tracking_screen.dart';
import '../features/alerts/presentation/screens/alerts_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/history/presentation/screens/history_screen.dart';
import '../features/vehicles/presentation/screens/dashboard_screen.dart';
import '../shared/models/app_models.dart';
import '../shared/models/auth_session.dart';
import '../shared/services/app_providers.dart';

class AppRoutes {
  AppRoutes._();

  static const splash = '/';
  static const login = '/login';
  static const dashboard = '/dashboard';
  static const history = '/history';
  static const admin = '/admin';
  static const tracking = '/tracking';
  static const fleetDashboard = '/fleet-dashboard';
  static const alerts = '/alerts';
}

class RouterNotifier extends ChangeNotifier {
  RouterNotifier(this.ref) {
    ref.listen<AuthSession>(authControllerProvider, (_, __) => notifyListeners());
  }

  final Ref ref;
}

final routerNotifierProvider = Provider<RouterNotifier>((ref) {
  final notifier = RouterNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

String? resolveRedirect(GoRouterState state, AuthSession session) {
  final location = state.matchedLocation;

  if (!session.isReady) {
    return location == AppRoutes.splash ? null : AppRoutes.splash;
  }

  final user = session.user;

  if (location == AppRoutes.splash) {
    if (user == null) return AppRoutes.login;
    return AppRoutes.dashboard;
  }

  if (user == null && location != AppRoutes.login) {
    return AppRoutes.login;
  }

  if (user != null && location == AppRoutes.login) {
    return AppRoutes.dashboard;
  }

  if (location == AppRoutes.admin && user?.role != UserRole.admin) {
    return AppRoutes.dashboard;
  }

  if (location == AppRoutes.tracking && user?.role != UserRole.admin) {
    return AppRoutes.dashboard;
  }

  if (location == AppRoutes.fleetDashboard && user?.role != UserRole.admin) {
    return AppRoutes.dashboard;
  }

  if (location == AppRoutes.alerts && user?.role != UserRole.admin) {
    return AppRoutes.dashboard;
  }

  return null;
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: notifier,
    redirect: (context, state) => resolveRedirect(state, ref.read(authControllerProvider)),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainAppShell(child: child),
        routes: [
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
          GoRoute(
            path: AppRoutes.tracking,
            builder: (context, state) => const TrackingScreen(),
          ),
          GoRoute(
            path: AppRoutes.fleetDashboard,
            builder: (context, state) => const FleetDashboardScreen(),
          ),
          GoRoute(
            path: AppRoutes.alerts,
            builder: (context, state) => const AlertsScreen(),
          ),
        ],
      ),
    ],
  );
});
