import 'package:flutter/material.dart';

/// Shared visual language for the Nisa member and administration surfaces.
///
/// Keep this layer presentation-only: auth, discovery, moderation, and profile
/// behavior remains owned by their existing screens and services.
abstract final class NisaTheme {
  static const Color _plum = Color(0xFF67394F);
  static const Color _rose = Color(0xFF8D6074);
  static const Color _gold = Color(0xFF9A6F3F);
  static const Color _canvas = Color(0xFFF8F5F2);
  static const Color _surface = Color(0xFFFFFEFC);
  static const Color _surfaceSoft = Color(0xFFF2ECEF);
  static const Color _outline = Color(0xFFE8DFE4);
  static const Color _ink = Color(0xFF292329);
  static const Color _mutedInk = Color(0xFF6E646B);

  static ThemeData get light {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _plum,
          brightness: Brightness.light,
        ).copyWith(
          primary: _plum,
          onPrimary: Colors.white,
          secondary: _rose,
          onSecondary: Colors.white,
          tertiary: _gold,
          surface: _surface,
          onSurface: _ink,
          surfaceContainerLowest: _surface,
          surfaceContainerLow: _canvas,
          surfaceContainer: _surfaceSoft,
          outline: _outline,
          outlineVariant: _outline,
        );

    final roundedCard = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: _outline),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _outline),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'sans',
      colorScheme: scheme,
      scaffoldBackgroundColor: _canvas,
      dividerColor: _outline,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        backgroundColor: _surface,
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: _ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: _surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: roundedCard,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: _surfaceSoft,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _plum, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
        labelStyle: const TextStyle(color: _mutedInk),
        hintStyle: const TextStyle(color: _mutedInk),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          side: const BorderSide(color: _outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _surfaceSoft,
        selectedColor: const Color(0xFFE9DDE4),
        side: const BorderSide(color: _outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: const TextStyle(color: _ink, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: _plum,
        linearTrackColor: _surfaceSoft,
        circularTrackColor: _surfaceSoft,
      ),
      textTheme: Typography.material2021().black.apply(
        bodyColor: _ink,
        displayColor: _ink,
      ),
    );
  }
}
