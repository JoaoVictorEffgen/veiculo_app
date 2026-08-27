import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../shared/models/app_models.dart';
import '../../shared/services/app_providers.dart';

class MainAppShell extends ConsumerWidget {
  const MainAppShell({super.key, required this.child});

  final Widget child;

  int _adminSelectedIndex(String location) {
    if (location.startsWith(AppRoutes.fleetDashboard)) return 0;
    if (location.startsWith(AppRoutes.tracking)) return 1;
    if (location.startsWith(AppRoutes.dashboard)) return 2;
    if (location.startsWith(AppRoutes.checklists)) return 3;
    if (location.startsWith(AppRoutes.alerts)) return 4;
    if (location.startsWith(AppRoutes.admin)) return 5;
    return 2;
  }

  int _driverSelectedIndex(String location) {
    if (location.startsWith(AppRoutes.reports)) return 1;
    if (location.startsWith(AppRoutes.checklists)) return 2;
    if (location.startsWith(AppRoutes.history)) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final isAdmin = user?.role == UserRole.admin;
    final location = GoRouterState.of(context).matchedLocation;
    final unreadAlerts = isAdmin ? ref.watch(unreadAdminAlertsCountProvider) : 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: isAdmin
          ? _AdminBottomNav(
              selectedIndex: _adminSelectedIndex(location),
              unreadAlerts: unreadAlerts,
              onTap: (index) => _onAdminTap(context, index),
            )
          : _DriverBottomNav(
              selectedIndex: _driverSelectedIndex(location),
              onVehicles: () => context.go(AppRoutes.dashboard),
              onReports: () => context.go(AppRoutes.reports),
              onChecklists: () => context.go(AppRoutes.checklists),
              onHistory: () => context.go(AppRoutes.history),
            ),
    );
  }

  void _onAdminTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go(AppRoutes.fleetDashboard);
      case 1:
        context.go(AppRoutes.tracking);
      case 2:
        context.go(AppRoutes.dashboard);
      case 3:
        context.go(AppRoutes.checklists);
      case 4:
        context.go(AppRoutes.alerts);
      case 5:
        context.go(AppRoutes.admin);
    }
  }
}

class _AdminBottomNav extends StatelessWidget {
  const _AdminBottomNav({
    required this.selectedIndex,
    required this.unreadAlerts,
    required this.onTap,
  });

  final int selectedIndex;
  final int unreadAlerts;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              _NavItem(
                icon: Icons.speed_outlined,
                selectedIcon: Icons.speed,
                label: 'Dashboard',
                selected: selectedIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.map_outlined,
                selectedIcon: Icons.map,
                label: 'Mapa',
                selected: selectedIndex == 1,
                onTap: () => onTap(1),
              ),
              _NavItem(
                icon: Icons.directions_car_outlined,
                selectedIcon: Icons.directions_car_filled,
                label: 'Veiculos',
                selected: selectedIndex == 2,
                onTap: () => onTap(2),
              ),
              _NavItem(
                icon: Icons.checklist_rtl,
                selectedIcon: Icons.checklist_rtl,
                label: 'Checklists',
                selected: selectedIndex == 3,
                onTap: () => onTap(3),
              ),
              _NavItem(
                icon: Icons.notifications_outlined,
                selectedIcon: Icons.notifications,
                label: 'Alertas',
                selected: selectedIndex == 4,
                badgeCount: unreadAlerts,
                onTap: () => onTap(4),
              ),
              _NavItem(
                icon: Icons.menu,
                selectedIcon: Icons.menu_open,
                label: 'Menu',
                selected: selectedIndex == 5,
                onTap: () => onTap(5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverBottomNav extends StatelessWidget {
  const _DriverBottomNav({
    required this.selectedIndex,
    required this.onVehicles,
    required this.onReports,
    required this.onChecklists,
    required this.onHistory,
  });

  final int selectedIndex;
  final VoidCallback onVehicles;
  final VoidCallback onReports;
  final VoidCallback onChecklists;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              _NavItem(
                icon: Icons.directions_car_outlined,
                selectedIcon: Icons.directions_car_filled,
                label: 'Veiculos',
                selected: selectedIndex == 0,
                onTap: onVehicles,
              ),
              _NavItem(
                icon: Icons.report_outlined,
                selectedIcon: Icons.report,
                label: 'Relatos',
                selected: selectedIndex == 1,
                onTap: onReports,
              ),
              _NavItem(
                icon: Icons.checklist_rtl,
                selectedIcon: Icons.checklist_rtl,
                label: 'Checklists',
                selected: selectedIndex == 2,
                onTap: onChecklists,
              ),
              _NavItem(
                icon: Icons.history,
                selectedIcon: Icons.history,
                label: 'Historico',
                selected: selectedIndex == 3,
                onTap: onHistory,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.navInactive;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(selected ? selectedIcon : icon, color: color, size: 22),
                  if (badgeCount > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        decoration: const BoxDecoration(
                          color: AppColors.statusStopped,
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: Text(
                          badgeCount > 9 ? '9+' : '$badgeCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

class CorporateAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const CorporateAppBar({
    super.key,
    required this.title,
    this.showBack = false,
    this.actions,
  });

  final String title;
  final bool showBack;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.dashboard),
            )
          : null,
      title: Text(title.toUpperCase()),
      actions: actions ??
          [
            IconButton(
              onPressed: () => context.go(AppRoutes.history),
              icon: const Icon(Icons.history),
              tooltip: 'Historico',
            ),
            IconButton(
              onPressed: () async {
                await ref.read(authControllerProvider.notifier).logout();
                if (context.mounted) context.go(AppRoutes.login);
              },
              icon: const Icon(Icons.logout),
              tooltip: 'Sair',
            ),
          ],
    );
  }
}

class FleetSection extends StatelessWidget {
  const FleetSection({
    super.key,
    required this.title,
    required this.count,
    required this.headerColor,
    required this.children,
  });

  final String title;
  final int count;
  final Color headerColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: headerColor,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$title ($count)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ],
      ),
    );
  }
}

class FleetInfoRow extends StatelessWidget {
  const FleetInfoRow({super.key, required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.35),
                children: [
                  TextSpan(text: '$label: ', style: const TextStyle(color: AppColors.textSecondary)),
                  TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
