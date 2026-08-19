import 'package:flutter/material.dart';

/// Paleta e componentes centrais do app.
///
/// Objetivo de design (conforme especificação):
/// - interface simples, profissional e moderna
/// - fácil de usar com uma mão
/// - botões grandes
/// - poucos elementos visuais, foco total em status EM MOVIMENTO / PARADO
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF1E3A5F); // azul corporativo
  static const Color background = Color(0xFFF5F6F8);
  static const Color surface = Colors.white;

  static const Color statusMoving = Color(0xFF2E7D32); // verde
  static const Color statusStopped = Color(0xFFC62828); // vermelho
  static const Color statusMovingBg = Color(0xFFE8F5E9);
  static const Color statusStoppedBg = Color(0xFFFDECEA);

  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B7280);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.background,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 1,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      // Botões grandes, alvo mínimo de toque confortável (>= 52px de altura)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
