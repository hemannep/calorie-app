import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models.dart';
import '../theme/kayleo_colors.dart';
import '../theme/kayleo_radius.dart';
import '../theme/kayleo_spacing.dart';

export '../theme/kayleo_colors.dart';
export '../theme/kayleo_radius.dart';
export '../theme/kayleo_spacing.dart';
export '../theme/kayleo_theme.dart';

// Short semantic aliases keep existing screens compatible with the new system.
const forest = KayleoColors.forest;
const ink = KayleoColors.ink;
const muted = KayleoColors.muted;
const canvas = KayleoColors.cream;
const line = KayleoColors.line;
const lime = KayleoColors.lime;
const mint = KayleoColors.sage;
const orange = KayleoColors.carbs;
const blue = KayleoColors.hydration;

/// Kayleo's wordmark complements the K-and-leaf launcher mark.
class Brand extends StatelessWidget {
  const Brand({
    super.key,
    this.light = false,
    this.size = 30,
    this.visibleCharacters,
  });
  final bool light;
  final double size;

  /// Optional splash reveal: six letters followed by the accent dot.
  final int? visibleCharacters;
  @override
  Widget build(BuildContext context) {
    final count = visibleCharacters?.clamp(0, 7) ?? 7;
    return Semantics(
      label: 'Kayleo',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'kayleo'.substring(0, count.clamp(0, 6)),
              style: TextStyle(
                color: light || Theme.of(context).brightness == Brightness.dark
                    ? KayleoColors.white
                    : context.kayleoText,
              ),
            ),
            if (count == 7)
              const TextSpan(
                text: '.',
                style: TextStyle(color: lime),
              ),
          ],
        ),
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.4,
        ),
      ),
    );
  }
}

class KayleoDot extends StatelessWidget {
  const KayleoDot({super.key, this.size = 10, this.color = lime});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = KayleoSpacing.card,
    this.color,
    this.border = false,
  });
  final Widget child;
  final double padding;
  final Color? color;
  final bool border;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(KayleoRadius.large),
      boxShadow: Theme.of(context).brightness == Brightness.light
          ? const [
              BoxShadow(
                color: Color(0x06000000),
                blurRadius: 18,
                offset: Offset(0, 5),
              ),
            ]
          : null,
    ),
    child: Material(
      color: color == null
          ? context.kayleoSurfaces.card
          : _surfaceColor(context, color!),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KayleoRadius.large),
        side: border
            ? BorderSide(
                color:
                    (Theme.of(context).extension<KayleoSurfaces>()?.border ??
                    line),
              )
            : BorderSide(
                color: context.kayleoSurfaces.border.withValues(alpha: .65),
              ),
      ),
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    ),
  );
}

class Tag extends StatelessWidget {
  const Tag(
    this.text, {
    super.key,
    this.color = mint,
    this.textColor = forest,
    this.icon,
  });
  final String text;
  final Color color, textColor;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: _surfaceColor(context, color),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 13,
            color: _foregroundColor(context, textColor, color),
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ).copyWith(color: _foregroundColor(context, textColor, color)),
          ),
        ),
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: KayleoSpacing.lg),
    child: SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: KayleoSpacing.lg,
        runSpacing: KayleoSpacing.sm,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(action!, style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: KayleoSpacing.sm),
                  const Icon(Icons.arrow_forward_rounded, size: 16),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class PageTitle extends StatelessWidget {
  const PageTitle(
    this.eyebrow,
    this.title,
    this.subtitle, {
    super.key,
    this.trailing,
  });
  final String eyebrow, title, subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: KayleoSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: KayleoSpacing.lg,
          runSpacing: KayleoSpacing.sm,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            ?trailing,
          ],
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: KayleoSpacing.sm),
          Text(
            subtitle,
            style: TextStyle(
              color: context.kayleoMuted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ],
    ),
  );
}

class FoodPhoto extends StatelessWidget {
  const FoodPhoto({
    super.key,
    required this.image,
    this.meal,
    this.width,
    this.height,
    this.radius = 16,
  });
  final String image;
  final Meal? meal;
  final double? width, height;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: meal?.photo != null
        ? Image.memory(
            meal!.photo!,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _asset(context),
          )
        : _asset(context),
  );
  Widget _asset(BuildContext context) => Image.asset(
    'assets/images/$image.jpg',
    width: width,
    height: height,
    fit: BoxFit.cover,
    errorBuilder: (_, _, _) => Container(
      width: width,
      height: height,
      color: context.kayleoSurfaces.soft,
      child: Icon(Icons.restaurant_rounded, color: context.kayleoPrimary),
    ),
  );
}

class IconBox extends StatelessWidget {
  const IconBox(
    this.icon, {
    super.key,
    this.color = mint,
    this.foreground = forest,
    this.size = 42,
  });
  final IconData icon;
  final Color color, foreground;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: _surfaceColor(context, color),
      borderRadius: BorderRadius.circular(KayleoRadius.small),
    ),
    child: Icon(
      icon,
      size: size * .48,
      color: _foregroundColor(context, foreground, color),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final IconData icon;
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: KayleoSpacing.xxl),
    child: Center(
      child: Column(
        children: [
          IconBox(icon, size: 60),
          const SizedBox(height: KayleoSpacing.lg),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: KayleoSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.kayleoMuted,
                fontSize: 13,
                height: 1.7,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: KayleoSpacing.page),
            action!,
          ],
        ],
      ),
    ),
  );
}

enum KayleoRingState {
  idle,
  progress,
  listening,
  scanning,
  analyzing,
  complete,
  success,
}

/// A calm, accessible ring shared by daily nutrition and meal activity.
class KayleoRing extends StatelessWidget {
  const KayleoRing({
    super.key,
    required this.progress,
    required this.child,
    this.size = 180,
    this.color = forest,
    this.track = mint,
    this.stroke = 12,
    this.state = KayleoRingState.progress,
    this.semanticLabel,
    this.highlight = true,
    this.segmented = false,
  });
  final double progress, size, stroke;
  final Color color, track;
  final Widget child;
  final KayleoRingState state;
  final String? semanticLabel;
  final bool highlight;
  final bool segmented;
  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: TweenAnimationBuilder<double>(
      tween: Tween(
        end: segmented ? math.max(0, progress) : progress.clamp(0, 1),
      ),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 320),
      builder: (_, value, content) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(
            value,
            switch (state) {
              KayleoRingState.listening ||
              KayleoRingState.scanning ||
              KayleoRingState.analyzing ||
              KayleoRingState.success => lime,
              _ => color,
            },
            track == mint ? context.kayleoSurfaces.soft : track,
            stroke,
            highlight: highlight && state == KayleoRingState.progress,
            segmented: segmented,
          ),
          child: Center(child: content),
        ),
      ),
      child: child,
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(
    this.progress,
    this.color,
    this.track,
    this.stroke, {
    this.highlight = false,
    this.segmented = false,
  });
  final bool highlight;
  final bool segmented;
  final double progress, stroke;
  final Color color, track;
  @override
  void paint(Canvas canvas, Size size) {
    final inset = segmented && progress > 1 ? stroke + 4 : 0.0;
    final rect = Rect.fromLTWH(
      stroke / 2 + inset,
      stroke / 2 + inset,
      size.width - stroke - inset * 2,
      size.height - stroke - inset * 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (segmented) {
      paint.strokeCap = StrokeCap.butt;
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2,
        false,
        paint..color = track,
      );
      const parts = [
        (0.0, .3, forest),
        (.3, .7, Color(0xFF6B9F52)),
        (.7, 1.0, lime),
      ];
      for (final part in parts) {
        final end = math.min(progress, part.$2);
        if (end <= part.$1) continue;
        canvas.drawArc(
          rect,
          -math.pi / 2 + math.pi * 2 * part.$1,
          math.pi * 2 * (end - part.$1),
          false,
          paint..color = part.$3,
        );
      }
      if (progress > 1) {
        final outer = Rect.fromLTWH(
          stroke / 2,
          stroke / 2,
          size.width - stroke,
          size.height - stroke,
        );
        canvas.drawArc(
          outer,
          -math.pi / 2,
          math.pi * 2,
          false,
          paint..color = track,
        );
        canvas.drawArc(
          outer,
          -math.pi / 2,
          math.pi * 2 * (progress - 1).clamp(0, 1),
          false,
          paint..color = orange,
        );
      }
      return;
    }
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2,
      false,
      paint..color = track,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0, 1),
      false,
      paint..color = color,
    );
    if (highlight && progress > .015) {
      final sweep = math.pi * 2 * progress.clamp(0, 1);
      final accent = math.min(sweep, .48);
      canvas.drawArc(
        rect,
        -math.pi / 2 + sweep - accent,
        accent,
        false,
        paint..color = lime,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.track != track ||
      old.stroke != stroke ||
      old.highlight != highlight ||
      old.segmented != segmented;
}

class MacroBar extends StatelessWidget {
  const MacroBar(this.label, this.value, this.target, this.color, {super.key});
  final String label;
  final double value;
  final int target;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: context.kayleoMuted),
          ),
        ],
      ),
      const SizedBox(height: KayleoSpacing.sm),
      RichText(
        text: TextSpan(
          style: TextStyle(fontFamily: 'Manrope', color: context.kayleoText),
          children: [
            TextSpan(
              text: '${value.round()}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            TextSpan(
              text: ' / ${target}g',
              style: TextStyle(fontSize: 10, color: context.kayleoMuted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: LinearProgressIndicator(
          value: (value / math.max(target, 1)).clamp(0, 1),
          minHeight: 5,
          color: color,
          backgroundColor: color.withValues(alpha: .14),
        ),
      ),
    ],
  );
}

class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.onBack,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: line,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              KayleoSpacing.xl,
              KayleoSpacing.lg,
              KayleoSpacing.lg,
              14,
            ),
            child: Row(
              children: [
                if (onBack != null)
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: KayleoSpacing.xs),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: context.kayleoMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(KayleoSpacing.xl),
              child: child,
            ),
          ),
          if (footer != null)
            Container(
              padding: const EdgeInsets.fromLTRB(
                KayleoSpacing.xl,
                KayleoSpacing.lg,
                KayleoSpacing.xl,
                KayleoSpacing.page,
              ),
              decoration: BoxDecoration(
                color: context.kayleoSurfaces.card,
                border: Border(
                  top: BorderSide(color: context.kayleoSurfaces.border),
                ),
              ),
              child: footer,
            ),
        ],
      ),
    ),
  );
}

Future<T?> openSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: 720,
        maxHeight: MediaQuery.sizeOf(context).height * .92,
      ),
      builder: (_) => child,
    );

void toast(BuildContext context, String text, {SnackBarAction? action}) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        action: action,
        duration: const Duration(seconds: 3),
      ),
    );
String number(num n) => NumberFormat.decimalPattern().format(n.round());
String friendlyDate(DateTime date) => DateFormat('EEE, d MMM').format(date);

// A popped dialog remains mounted during its closing transition. Keep its
// controllers alive until the route has actually finished, rather than using
// a timer that can race a slow frame or an accessibility animation setting.
Future<T?> showManagedDialog<T>({
  required BuildContext context,
  required List<TextEditingController> controllers,
  required WidgetBuilder builder,
}) async {
  final route = DialogRoute<T>(context: context, builder: builder);
  final result = await Navigator.of(context).push(route);
  unawaited(
    route.completed.then<void>((_) {
      for (final controller in controllers) {
        controller.dispose();
      }
    }),
  );
  return result;
}

Color _surfaceColor(BuildContext context, Color color) {
  if (color == mint) return context.kayleoSurfaces.soft;
  if (color == canvas) return context.kayleoBackground;
  if (color == Colors.white) return context.kayleoSurfaces.card;
  return color;
}

Color _foregroundColor(BuildContext context, Color color, Color background) {
  if (color == forest && (background == lime || background == forest)) {
    return forest;
  }
  if (color == muted) return context.kayleoMuted;
  if (color == ink) return context.kayleoText;
  if (color == forest && background != lime && background != forest) {
    return context.kayleoPrimary;
  }
  return color;
}
