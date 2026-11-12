import 'package:flutter/material.dart';

/// The only place where raw colour values live. Screens use [AppColors] constants or the
/// brightness-aware [AppPalette] (`context.palette`), never colour literals.
class AppColors {
  const AppColors._();

  // Brand and semantic colours (same in light and dark).
  static const Color primary = Color(0xFF6366F1);
  static const Color secondary = Color(0xFF8B5CF6);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Light surfaces.
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);
  static const Color softPrimary = Color(0xFFEEF2FF);

  // Dark surfaces (slate scale, chosen to keep the brand indigo readable: AA contrast on #0F172A).
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkTextPrimary = Color(0xFFF1F5F9);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkSoftPrimary = Color(0xFF312E81);
  /// Primary tone used for text/icons on dark surfaces (the brand indigo is too dark for small text there).
  static const Color primaryOnDark = Color(0xFFA5B4FC);

  // Splash / hero gradient (matches the concept art: deep navy to indigo).
  static const Color heroStart = Color(0xFF0F172A);
  static const Color heroMiddle = Color(0xFF1E1B4B);
  static const Color heroEnd = Color(0xFF3730A3);

  /// Tinted backgrounds for status chips (computed from the semantic colours).
  static Color tint(Color c, {double alpha = 0.12}) => c.withValues(alpha: alpha);
}

/// Brightness-aware colours for the current theme.
class AppPalette {
  const AppPalette._({
    required this.background,
    required this.surface,
    required this.border,
    required this.text,
    required this.textSecondary,
    required this.softPrimary,
    required this.primaryText,
    required this.isDark,
  });

  final Color background;
  final Color surface;
  final Color border;
  final Color text;
  final Color textSecondary;
  final Color softPrimary;

  /// Indigo that is legible as text/icon colour on the current surface.
  final Color primaryText;
  final bool isDark;

  static const AppPalette light = AppPalette._(
    background: AppColors.background,
    surface: AppColors.surface,
    border: AppColors.border,
    text: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    softPrimary: AppColors.softPrimary,
    primaryText: AppColors.primary,
    isDark: false,
  );

  static const AppPalette dark = AppPalette._(
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    border: AppColors.darkBorder,
    text: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    softPrimary: AppColors.darkSoftPrimary,
    primaryText: AppColors.primaryOnDark,
    isDark: true,
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette => AppPalette.of(this);
}
