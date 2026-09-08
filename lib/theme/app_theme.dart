// Light + dark themes for the app.
//
// The visual language is loosely based on the z.ai website (light grey
// background, indigo accent on the main brand mark), but the palette
// itself is intentionally our own — we don't want to fork the look every
// time z.ai redesigns.

import 'package:flutter/material.dart';

/// Colours that we reuse across light/dark themes. Tweaking here propagates
/// to both [lightTheme] and [darkTheme].
class AppColors {
  AppColors._();

  // Brand accent — purple/violet (Lagerstroemia is the crape myrtle genus,
  // which has signature pink-purple blossoms).
  static const Color accent = Color(0xFF7C4DFF);
  static const Color accentSoft = Color(0xFFB388FF);

  // Light theme
  static const Color lightBg = Color(0xFFF7F8FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFEFF1F5);
  static const Color lightText = Color(0xFF15171A);
  static const Color lightTextMuted = Color(0xFF5F6368);

  // Dark theme
  static const Color darkBg = Color(0xFF0E1014);
  static const Color darkSurface = Color(0xFF15181E);
  static const Color darkSurfaceAlt = Color(0xFF1E222A);
  static const Color darkText = Color(0xFFE8E9ED);
  static const Color darkTextMuted = Color(0xFF9AA0AA);

  // User message bubble (assistant bubble uses surface).
  static const Color userBubbleLight = Color(0xFFE8EAF6);
  static const Color userBubbleDark = Color(0xFF1F2230);
}

final ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: const ColorScheme.light(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    secondary: AppColors.accentSoft,
    onSecondary: Colors.black,
    surface: AppColors.lightSurface,
    onSurface: AppColors.lightText,
  ),
  scaffoldBackgroundColor: AppColors.lightBg,
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.lightSurface,
    foregroundColor: AppColors.lightText,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
  ),
  listTileTheme: const ListTileThemeData(
    iconColor: AppColors.accent,
  ),
  cardTheme: CardThemeData(
    color: AppColors.lightSurface,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
    ),
  ),
  dividerTheme: const DividerThemeData(
    color: Color(0xFFE5E7EB),
    thickness: 1,
    space: 1,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.lightSurfaceAlt,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE0E2E6), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: ButtonStyle(
      foregroundColor: WidgetStateProperty.all(AppColors.accent),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: ButtonStyle(
      backgroundColor: WidgetStateProperty.all(AppColors.accent),
      foregroundColor: WidgetStateProperty.all(Colors.white),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  ),
);

final ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    secondary: AppColors.accentSoft,
    onSecondary: Colors.black,
    surface: AppColors.darkSurface,
    onSurface: AppColors.darkText,
  ),
  scaffoldBackgroundColor: AppColors.darkBg,
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.darkSurface,
    foregroundColor: AppColors.darkText,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
  ),
  listTileTheme: const ListTileThemeData(
    iconColor: AppColors.accent,
  ),
  cardTheme: CardThemeData(
    color: AppColors.darkSurface,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0xFF2A2E37), width: 1),
    ),
  ),
  dividerTheme: const DividerThemeData(
    color: Color(0xFF2A2E37),
    thickness: 1,
    space: 1,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.darkSurfaceAlt,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF2A2E37), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: ButtonStyle(
      foregroundColor: WidgetStateProperty.all(AppColors.accent),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: ButtonStyle(
      backgroundColor: WidgetStateProperty.all(AppColors.accent),
      foregroundColor: WidgetStateProperty.all(Colors.white),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  ),
);
