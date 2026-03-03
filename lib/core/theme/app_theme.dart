import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens from the reference style guide.
class AppColors {
  AppColors._();

  // Core palette
  static const Color yellow = Color(0xFF7D4698);
  static const Color darkBg = Color(0xFF0E121A);
  static const Color lightSurface = Color(0xFFF0F0F0);
  static const Color coral = Color(0xFFFC574E);
  static const Color mint = Color(0xFF489E3B);

  // Derived
  static const Color darkSurface = Color(0xFF161B25);
  static const Color darkCard = Color(0xFF1C2230);
  static const Color darkCardHigher = Color(0xFF242A38);
  static const Color yellowDark = Color(0xFF5C3472);
  static const Color textPrimary = Color(0xFFF5F5F5);
  static const Color textSecondary = Color(0xFFa0a6b4);
  static const Color outline = Color(0xFF2C3345);
}

class AppTheme {
  AppTheme._();

  /// The custom dark [ColorScheme] matching the reference palette.
  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    // Primary — yellow
    primary: AppColors.yellow,
    onPrimary: AppColors.darkBg,
    primaryContainer: Color(0xFF2E1940),
    onPrimaryContainer: AppColors.yellow,
    // Secondary — mint green
    secondary: AppColors.mint,
    onSecondary: AppColors.darkBg,
    secondaryContainer: Color(0xFF1A3318),
    onSecondaryContainer: AppColors.mint,
    // Tertiary — coral
    tertiary: AppColors.coral,
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFF3A1614),
    onTertiaryContainer: AppColors.coral,
    // Error
    error: AppColors.coral,
    onError: Colors.white,
    errorContainer: Color(0xFF3A1614),
    onErrorContainer: AppColors.coral,
    // Surfaces
    surface: AppColors.darkBg,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    // Containers
    surfaceContainerLowest: AppColors.darkBg,
    surfaceContainerLow: AppColors.darkSurface,
    surfaceContainer: AppColors.darkCard,
    surfaceContainerHigh: AppColors.darkCardHigher,
    surfaceContainerHighest: Color(0xFF2A3040),
    // Outline 
    outline: AppColors.outline,
    outlineVariant: Color(0xFF232A38),
    // Misc
    inverseSurface: AppColors.lightSurface,
    onInverseSurface: AppColors.darkBg,
    inversePrimary: AppColors.yellowDark,
    shadow: Colors.black,
    scrim: Colors.black,
  );

  /// Build [TextTheme] using Barlow Semi Condensed.
  static TextTheme _buildTextTheme() {
    final base = GoogleFonts.barlowSemiCondensedTextTheme(
      ThemeData.dark().textTheme,
    );
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(fontWeight: FontWeight.w800),
      displayMedium: base.displayMedium?.copyWith(fontWeight: FontWeight.w700),
      displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.w700),
      headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
      headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: base.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      bodyMedium: base.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      bodySmall: base.bodySmall?.copyWith(fontWeight: FontWeight.w400),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.4),
      labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: base.labelSmall?.copyWith(fontWeight: FontWeight.w500),
    );
  }

  /// The single dark theme for OnionTalkie.
  static ThemeData darkTheme() {
    const cs = _darkScheme;
    final textTheme = _buildTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: cs,
      textTheme: textTheme,
      scaffoldBackgroundColor: cs.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: cs.onSurface,
          fontSize: 22,
        ),
        iconTheme: IconThemeData(color: cs.primary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cs.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
          foregroundColor: cs.primary,
          side: BorderSide(color: cs.primary.withValues(alpha: 0.4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cs.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: cs.onSurface,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: TextStyle(color: cs.onSurfaceVariant),
        hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return cs.primary;
          return cs.onSurfaceVariant;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return cs.primary.withValues(alpha: 0.35);
          }
          return cs.outline;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cs.surfaceContainer,
        selectedColor: cs.primary.withValues(alpha: 0.2),
        side: BorderSide(color: cs.outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        labelStyle: textTheme.labelSmall,
      ),
      dividerTheme: DividerThemeData(
        color: cs.outline.withValues(alpha: 0.5),
        thickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: cs.primary,
        textColor: cs.onSurface,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.surfaceContainerHigh,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: cs.onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: cs.surfaceContainerLow,
        dragHandleColor: cs.outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(color: cs.onSurface),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: cs.surfaceContainerLow,
        indicatorColor: cs.primary.withValues(alpha: 0.2),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: cs.primary);
          }
          return IconThemeData(color: cs.onSurfaceVariant);
        }),
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: cs.primary,
        linearTrackColor: cs.outline,
        circularTrackColor: cs.outline,
      ),
    );
  }

  // Keep legacy methods for backward compat (both point to dark).
  static ThemeData fallbackLight() => darkTheme();
  static ThemeData fallbackDark() => darkTheme();

  /// Helper – kept for any code that calls fromColorScheme.
  static ThemeData fromColorScheme(ColorScheme colorScheme) => darkTheme();
}
