import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Radii and spacing used across the app (kept here so screens stay consistent).
class AppDims {
  const AppDims._();

  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 24;
  static const double pagePadding = 16;
  static const double minTouch = 48;
}

class AppTheme {
  const AppTheme._();

  static const String fontFamily = 'Cairo';

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    final AppPalette p = dark ? AppPalette.dark : AppPalette.light;
    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: dark ? AppColors.primaryOnDark : AppColors.primary,
      onPrimary: dark ? AppColors.darkBackground : AppColors.onPrimary,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onPrimary,
      error: AppColors.error,
      onError: AppColors.onPrimary,
      surface: p.surface,
      onSurface: p.text,
      outline: p.border,
      primaryContainer: p.softPrimary,
      onPrimaryContainer: dark ? AppColors.primaryOnDark : AppColors.primary,
    );

    final TextTheme base = ThemeData(brightness: brightness, fontFamily: fontFamily).textTheme;
    final TextTheme text = base.apply(bodyColor: p.text, displayColor: p.text, fontFamily: fontFamily);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: p.background,
      dividerColor: p.border,
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: p.text,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size.fromHeight(AppDims.minTouch),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDims.radiusMd)),
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.primaryText,
          minimumSize: const Size.fromHeight(AppDims.minTouch),
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDims.radiusMd)),
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primaryText,
          minimumSize: const Size(AppDims.minTouch, AppDims.minTouch),
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.softPrimary,
        elevation: 3,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((Set<WidgetState> states) {
          final bool selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: fontFamily,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? p.primaryText : p.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((Set<WidgetState> states) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? p.primaryText : p.textSecondary);
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDims.radiusSm)),
      ),
    );
  }
}
