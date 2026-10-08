import 'package:flutter/material.dart';

abstract final class KayleoTypography {
  static const fontFamily = 'Manrope';
  static TextTheme textTheme(Color text, Color secondary) => TextTheme(
    headlineLarge: TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.5,
      color: text,
    ),
    headlineMedium: TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      letterSpacing: -.9,
      color: text,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w800,
      letterSpacing: -.7,
      color: text,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w800,
      letterSpacing: -.5,
      color: text,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: text,
    ),
    bodyLarge: TextStyle(fontSize: 15, height: 1.6, color: text),
    bodyMedium: TextStyle(fontSize: 13, height: 1.6, color: text),
    bodySmall: TextStyle(fontSize: 11, height: 1.5, color: secondary),
    labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
  );
}
