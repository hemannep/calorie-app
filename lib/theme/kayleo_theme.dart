import 'package:flutter/material.dart';

import 'kayleo_colors.dart';
import 'kayleo_radius.dart';
import 'kayleo_spacing.dart';
import 'kayleo_typography.dart';

ThemeData kayleoTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final surfaces = dark ? KayleoSurfaces.dark : KayleoSurfaces.light;
  final text = dark ? KayleoColors.darkText : KayleoColors.ink;
  final secondaryText = dark ? KayleoColors.darkMuted : KayleoColors.muted;
  final background = dark ? KayleoColors.darkBackground : KayleoColors.cream;
  final primary = dark ? KayleoColors.lime : KayleoColors.forest;
  final scheme = ColorScheme.fromSeed(
    seedColor: KayleoColors.forest,
    brightness: brightness,
    primary: primary,
    onPrimary: dark ? KayleoColors.forest : KayleoColors.white,
    secondary: KayleoColors.lime,
    onSecondary: KayleoColors.forest,
    primaryContainer: surfaces.soft,
    onPrimaryContainer: text,
    secondaryContainer: surfaces.soft,
    onSecondaryContainer: text,
    surfaceTint: Colors.transparent,
    surface: surfaces.card,
    onSurface: text,
    onSurfaceVariant: secondaryText,
    error: KayleoColors.error,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: KayleoTypography.fontFamily,
    scaffoldBackgroundColor: background,
    colorScheme: scheme,
    extensions: [surfaces],
    textTheme: KayleoTypography.textTheme(text, secondaryText),
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaces.card,
      selectedColor: surfaces.soft,
      side: BorderSide(color: surfaces.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelStyle: TextStyle(
        fontFamily: KayleoTypography.fontFamily,
        color: text,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size(
          KayleoSpacing.touchTarget,
          KayleoSpacing.buttonHeight,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: KayleoSpacing.xl,
          vertical: KayleoSpacing.lg,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KayleoRadius.medium),
        ),
        textStyle: const TextStyle(
          fontFamily: KayleoTypography.fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        minimumSize: const Size(
          KayleoSpacing.touchTarget,
          KayleoSpacing.touchTarget,
        ),
        side: BorderSide(color: surfaces.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KayleoRadius.medium),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(
          KayleoSpacing.touchTarget,
          KayleoSpacing.touchTarget,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(
          KayleoSpacing.touchTarget,
          KayleoSpacing.touchTarget,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? background : KayleoColors.cream,
      contentPadding: const EdgeInsets.all(KayleoSpacing.lg),
      hintStyle: TextStyle(fontSize: 14, color: secondaryText),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KayleoRadius.medium),
        borderSide: BorderSide(color: surfaces.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KayleoRadius.medium),
        borderSide: BorderSide(color: surfaces.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KayleoRadius.medium),
        borderSide: BorderSide(color: primary),
      ),
    ),
    dividerColor: surfaces.border,
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(KayleoRadius.hero),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: KayleoColors.forest,
      contentTextStyle: const TextStyle(color: KayleoColors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KayleoRadius.medium),
      ),
    ),
  );
}
