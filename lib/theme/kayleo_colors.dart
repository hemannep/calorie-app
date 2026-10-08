import 'package:flutter/material.dart';

/// Kayleo's semantic palette. Lime is reserved for actions and intelligence.
abstract final class KayleoColors {
  static const cream = Color(0xFFF7F5ED);
  static const forest = Color(0xFF163E2D);
  static const lime = Color(0xFFB8E36B);
  static const warmSurface = Color(0xFFFCFAF4);
  static const white = Color(0xFFFFFFFF);
  static const sage = Color(0xFFE4EBDD);
  static const ink = Color(0xFF17231D);
  static const muted = Color(0xFF626E64);
  static const line = Color(0xFFE2E6DC);
  static const protein = Color(0xFFF07894);
  static const carbs = Color(0xFFF1B963);
  static const fat = Color(0xFF9A7DDD);
  static const success = Color(0xFF67A96B);
  static const error = Color(0xFFAD514A);
  static const warning = Color(0xFF946322);
  static const warningSurface = Color(0xFFF3EBDD);
  static const camera = Color(0xFF0D120F);
  static const hydration = Color(0xFF6999B1);
  static const darkBackground = Color(0xFF101713);
  static const darkSurface = Color(0xFF17201A);
  static const darkText = Color(0xFFF4F3EA);
  static const darkMuted = Color(0xFFAAB3AA);
}

/// Theme-aware surfaces shared by every screen and sheet.
@immutable
class KayleoSurfaces extends ThemeExtension<KayleoSurfaces> {
  const KayleoSurfaces({
    required this.card,
    required this.soft,
    required this.border,
  });
  final Color card, soft, border;
  static const light = KayleoSurfaces(
    card: KayleoColors.warmSurface,
    soft: KayleoColors.sage,
    border: KayleoColors.line,
  );
  static const dark = KayleoSurfaces(
    card: KayleoColors.darkSurface,
    soft: Color(0xFF25362B),
    border: Color(0xFF354439),
  );
  @override
  KayleoSurfaces copyWith({Color? card, Color? soft, Color? border}) =>
      KayleoSurfaces(
        card: card ?? this.card,
        soft: soft ?? this.soft,
        border: border ?? this.border,
      );
  @override
  KayleoSurfaces lerp(covariant KayleoSurfaces? other, double t) =>
      other == null
      ? this
      : KayleoSurfaces(
          card: Color.lerp(card, other.card, t)!,
          soft: Color.lerp(soft, other.soft, t)!,
          border: Color.lerp(border, other.border, t)!,
        );
}

/// Semantic colors for feature screens, independent of the current brightness.
extension KayleoThemeContext on BuildContext {
  KayleoSurfaces get kayleoSurfaces =>
      Theme.of(this).extension<KayleoSurfaces>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? KayleoSurfaces.dark
          : KayleoSurfaces.light);
  Color get kayleoText => Theme.of(this).colorScheme.onSurface;
  Color get kayleoMuted => Theme.of(this).colorScheme.onSurfaceVariant;
  Color get kayleoPrimary => Theme.of(this).colorScheme.primary;
  Color get kayleoBackground => Theme.of(this).scaffoldBackgroundColor;
}
