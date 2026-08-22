import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../shared/services/app_providers.dart';

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

  Future<void> _login() async {
    setState(() => _loading = true);
    final error = await ref.read(authControllerProvider.notifier).login(_emailController.text, _passwordController.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (!mounted) return;
    context.go(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _AnimatedLoginHeader(),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Entre com seu usuario corporativo', textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.person_outline)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          onSubmitted: (_) => _login(),
                          decoration: const InputDecoration(labelText: 'Senha', prefixIcon: Icon(Icons.lock_outline)),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _loading ? null : _login,
                          icon: const Icon(Icons.login),
                          label: Text(_loading ? 'Entrando...' : 'Entrar'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedLoginHeader extends StatefulWidget {
  const _AnimatedLoginHeader();

  @override
  State<_AnimatedLoginHeader> createState() => _AnimatedLoginHeaderState();
}

class _AnimatedLoginHeaderState extends State<_AnimatedLoginHeader> with SingleTickerProviderStateMixin {
  static const _vehicleIcons = <IconData>[
    Icons.local_shipping_rounded,
    Icons.directions_car_rounded,
    Icons.directions_bus_rounded,
    Icons.airport_shuttle_rounded,
  ];

  static const _iconSize = 52.0;
  static const _roadPadding = 24.0;

  late final AnimationController _controller;
  late final Animation<double> _drive;
  var _vehicleIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    _drive = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.addStatusListener(_onAnimationStatus);
    _controller.forward();
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    setState(() => _vehicleIndex = (_vehicleIndex + 1) % _vehicleIcons.length);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onAnimationStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 88,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final roadWidth = constraints.maxWidth - (_roadPadding * 2);
                final maxOffset = roadWidth - _iconSize;

                return AnimatedBuilder(
                  animation: _drive,
                  builder: (context, child) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: _roadPadding,
                          right: _roadPadding,
                          bottom: 16,
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        Positioned(
                          left: _roadPadding,
                          right: _roadPadding,
                          bottom: 14,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(
                              6,
                              (_) => Container(
                                width: 14,
                                height: 2,
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: _roadPadding + (_drive.value * maxOffset),
                          bottom: 18,
                          child: child!,
                        ),
                      ],
                    );
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                    child: Icon(
                      _vehicleIcons[_vehicleIndex],
                      key: ValueKey(_vehicleIndex),
                      size: _iconSize,
                      color: Colors.white,
                    ),
                  ),
                );
              },
            ),
          ),
          const Text(
            'Controle de Veiculos',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Gestao corporativa da frota',
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
