import 'package:flutter/material.dart';

/// Paleta de obra: carbón + amarillo de seguridad sobre gris hormigón.
class AppColors {
  static const ink = Color(0xFF1C1F23);
  static const inkSoft = Color(0xFF2A2E34);
  static const yellow = Color(0xFFF5B700);
  static const yellowSoft = Color(0xFFFFF3CC);
  static const concrete = Color(0xFFF3F1EC);
  static const surface = Colors.white;
  static const line = Color(0xFFE2DED6);
  static const muted = Color(0xFF6B6F76);
  static const green = Color(0xFF2E7D32);
  static const greenSoft = Color(0xFFE6F2E7);
  static const red = Color(0xFFC62828);
  static const redSoft = Color(0xFFFBE9E9);
  static const orange = Color(0xFFE07A00);
  static const orangeSoft = Color(0xFFFFF0DC);
  static const blue = Color(0xFF1F5FAD);
  static const blueSoft = Color(0xFFE5EEF9);
}

class AppTheme {
  static const radius = 12.0;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.yellow, brightness: Brightness.light).copyWith(
      primary: AppColors.ink,
      onPrimary: Colors.white,
      primaryContainer: AppColors.yellowSoft,
      onPrimaryContainer: AppColors.ink,
      secondary: AppColors.yellow,
      onSecondary: AppColors.ink,
      secondaryContainer: AppColors.yellowSoft,
      onSecondaryContainer: AppColors.ink,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.muted,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AppColors.concrete,
      surfaceContainer: AppColors.concrete,
      surfaceContainerHigh: const Color(0xFFECE9E2),
      surfaceContainerHighest: const Color(0xFFE6E2DA),
      outline: const Color(0xFFBDB8AE),
      outlineVariant: AppColors.line,
      error: AppColors.red,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Barlow');
    final text = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
    );

    final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: AppColors.concrete,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.concrete,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: AppColors.ink, fontFamily: 'Barlow', fontSize: 22),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.ink,
        indicatorColor: AppColors.yellow,
        surfaceTintColor: Colors.transparent,
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? AppColors.ink : Colors.white70,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontFamily: 'Barlow',
              fontSize: 12,
              fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
              color: s.contains(WidgetState.selected) ? Colors.white : Colors.white70,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.ink,
        indicatorColor: AppColors.yellow,
        selectedIconTheme: const IconThemeData(color: AppColors.ink),
        unselectedIconTheme: const IconThemeData(color: Colors.white70),
        selectedLabelTextStyle: const TextStyle(fontFamily: 'Barlow', color: Colors.white, fontWeight: FontWeight.w700),
        unselectedLabelTextStyle: const TextStyle(fontFamily: 'Barlow', color: Colors.white70),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line, space: 1, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: AppColors.ink, width: 1.6)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: AppColors.red)),
        labelStyle: const TextStyle(color: AppColors.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.yellow,
          foregroundColor: AppColors.ink,
          disabledBackgroundColor: const Color(0xFFE6E2DA),
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 16),
          shape: rounded,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(64, 50),
          side: const BorderSide(color: AppColors.ink, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 15),
          shape: rounded,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.ink,
          textStyle: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.yellow,
        foregroundColor: AppColors.ink,
        elevation: 2,
        shape: rounded,
        extendedTextStyle: const TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700, fontSize: 15),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: AppColors.ink,
        secondarySelectedColor: AppColors.ink,
        checkmarkColor: AppColors.yellow,
        labelStyle: const TextStyle(fontFamily: 'Barlow', color: AppColors.ink, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(fontFamily: 'Barlow', color: Colors.white, fontWeight: FontWeight.w600),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.ink : Colors.white),
          foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.ink),
          iconColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.yellow : AppColors.ink),
          side: const WidgetStatePropertyAll(BorderSide(color: AppColors.line)),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: 'Barlow', fontWeight: FontWeight.w700)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.ink,
        titleTextStyle: TextStyle(fontFamily: 'Barlow', fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
        subtitleTextStyle: TextStyle(fontFamily: 'Barlow', fontSize: 13.5, color: AppColors.muted),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.concrete,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(fontFamily: 'Barlow', color: Colors.white, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.ink),
    );
  }
}
