import 'package:flutter/material.dart';

/// Palette de l'application, dérivée du logo (vert/orange/crème) — voir
/// "Nouvel interface.docx" (recommandations de refonte graphique, 2026-09-10).
/// Purement visuel : ne change aucune règle métier, seulement les couleurs.
class AppColors {
  AppColors._();

  static const Color green = Color(0xFF008A20);
  static const Color greenLight = Color(0xFFEEF8EF);
  static const Color orange = Color(0xFFF97316);
  static const Color orangeLight = Color(0xFFFFF1E6);
  static const Color background = Color(0xFFFFF9F5);
  static const Color textPrimary = Color(0xFF2B211B);
  static const Color textSecondary = Color(0xFF74675E);
  static const Color alert = Color(0xFFD64545);
  static const Color alertLight = Color(0xFFFCEAEA);
  static const Color white = Color(0xFFFFFFFF);
}

ThemeData buildAppTheme() {
  final colorScheme = const ColorScheme.light(
    primary: AppColors.green,
    onPrimary: AppColors.white,
    secondary: AppColors.orange,
    onSecondary: AppColors.white,
    error: AppColors.alert,
    onError: AppColors.white,
    surface: AppColors.white,
    onSurface: AppColors.textPrimary,
  );

  final base = ThemeData(colorScheme: colorScheme, useMaterial3: true);

  // Texte noir/anthracite partout dans l'application (demande explicite) :
  // `.apply` réécrit uniformément `bodyColor`/`displayColor` sur tout le
  // `TextTheme` généré par le thème plutôt que de fixer chaque style un par un.
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    primaryTextTheme: base.primaryTextTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      margin: EdgeInsets.zero,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.greenLight,
      selectedColor: AppColors.green,
      labelStyle: const TextStyle(color: AppColors.textPrimary),
      secondaryLabelStyle: const TextStyle(color: AppColors.white),
      side: BorderSide.none,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.white,
      selectedItemColor: AppColors.green,
      unselectedItemColor: AppColors.textSecondary,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.green,
        foregroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.green,
        side: const BorderSide(color: AppColors.green),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.orange,
      foregroundColor: AppColors.white,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      focusColor: AppColors.green,
      floatingLabelStyle: TextStyle(color: AppColors.green),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFE9E1D8)),
  );
}
