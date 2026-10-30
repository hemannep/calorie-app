import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/ui.dart';
import '../data/models.dart';

/// Introduces already calculated targets with a finite assembly animation.
class OnboardingPlanPreparation extends StatefulWidget {
  const OnboardingPlanPreparation({
    super.key,
    required this.profile,
    required this.onReady,
  });

  final BodyProfile profile;
  final VoidCallback onReady;

  @override
  State<OnboardingPlanPreparation> createState() =>
      _OnboardingPlanPreparationState();
}

class _OnboardingPlanPreparationState extends State<OnboardingPlanPreparation>
    with SingleTickerProviderStateMixin {
  late final AnimationController assembly;
  Timer? completion;
  bool started = false;

  @override
  void initState() {
    super.initState();
    assembly =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 2200),
        )..addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          completion?.cancel();
          completion = Timer(const Duration(milliseconds: 650), () {
            if (mounted) widget.onReady();
          });
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (started) return;
    started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      assembly.value = 1;
    } else {
      assembly.forward();
    }
  }

  @override
  void dispose() {
    completion?.cancel();
    assembly.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: assembly,
    builder: (context, _) {
      final progress = Curves.easeInOutCubic.transform(assembly.value);
      final ready = assembly.isCompleted;
      final stage = progress < .32
          ? 0
          : progress < .68
          ? 1
          : progress < .95
          ? 2
          : 3;
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      final profile = widget.profile;
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ExcludeSemantics(
              child: MediaQuery.withNoTextScaling(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = math.min(216.0, constraints.maxWidth * .66);
                    return SizedBox.square(
                      dimension: size,
                      child: CustomPaint(
                        painter: _BalanceRing(
                          progress: progress,
                          primary: context.kayleoPrimary,
                          track: context.kayleoSurfaces.soft,
                          border: context.kayleoSurfaces.border,
                        ),
                        child: Center(
                          child: Container(
                            width: size * .62,
                            height: size * .62,
                            decoration: const BoxDecoration(
                              color: forest,
                              shape: BoxShape.circle,
                            ),
                            child: AnimatedSwitcher(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              child: ready
                                  ? const Icon(
                                      Icons.check_rounded,
                                      key: ValueKey('ready'),
                                      size: 50,
                                      color: lime,
                                    )
                                  : Text.rich(
                                      key: const ValueKey('assembling'),
                                      TextSpan(
                                        children: [
                                          TextSpan(
                                            text: '${(progress * 100).round()}',
                                            style: const TextStyle(
                                              fontSize: 48,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -1.8,
                                            ),
                                          ),
                                          const TextSpan(
                                            text: '%',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        height: 1.1,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          LocalizedText(
            'Your plan,\nin balance.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: MediaQuery.textScalerOf(context).scale(14) > 20
                  ? 26
                  : 34,
              height: 1.1,
              letterSpacing: -1.4,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: LocalizedText(
                [
                  'Setting your daily energy',
                  'Finding your macro balance',
                  'Bringing your answers together',
                  'Your starting point is ready',
                ][stage],
                key: ValueKey(stage),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.kayleoMuted,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: context.kayleoSurfaces.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: context.kayleoSurfaces.border),
            ),
            child: Column(
              children: [
                _PreparationRow(
                  title: 'Daily energy',
                  detail: '${number(profile.calorieTarget)} calories',
                  complete: stage > 0,
                  active: stage == 0,
                  icon: Icons.wb_sunny_outlined,
                  reduceMotion: reduceMotion,
                ),
                Divider(
                  height: 1,
                  color: context.kayleoSurfaces.border.withValues(alpha: .7),
                ),
                _PreparationRow(
                  title: 'Protein, carbs & fat',
                  detail:
                      '${profile.proteinTarget}g · ${profile.carbTarget}g · ${profile.fatTarget}g',
                  complete: stage > 1,
                  active: stage == 1,
                  icon: Icons.donut_small_rounded,
                  reduceMotion: reduceMotion,
                ),
                Divider(
                  height: 1,
                  color: context.kayleoSurfaces.border.withValues(alpha: .7),
                ),
                _PreparationRow(
                  title: 'Your everyday rhythm',
                  detail: profile.activity,
                  complete: stage > 2,
                  active: stage == 2,
                  icon: Icons.spa_outlined,
                  reduceMotion: reduceMotion,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          LocalizedText(
            'A starting point. Always yours to adjust.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.5,
              color: context.kayleoMuted,
            ),
          ),
        ],
      );
    },
  );
}

class _PreparationRow extends StatelessWidget {
  const _PreparationRow({
    required this.title,
    required this.detail,
    required this.complete,
    required this.active,
    required this.icon,
    required this.reduceMotion,
  });

  final String title, detail;
  final bool complete, active, reduceMotion;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      children: [
        AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: complete || active
                ? context.kayleoSurfaces.soft
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(
            complete ? Icons.check_rounded : icon,
            size: 17,
            color: complete || active
                ? context.kayleoPrimary
                : context.kayleoMuted.withValues(alpha: .5),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LocalizedText(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: complete || active
                      ? context.kayleoText
                      : context.kayleoMuted,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedOpacity(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                opacity: complete ? 1 : 0,
                child: LocalizedText(
                  detail,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.kayleoMuted,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: complete
                ? context.kayleoPrimary
                : active
                ? lime
                : context.kayleoSurfaces.border,
            shape: BoxShape.circle,
          ),
        ),
      ],
    ),
  );
}

class _BalanceRing extends CustomPainter {
  const _BalanceRing({
    required this.progress,
    required this.primary,
    required this.track,
    required this.border,
  });
  final double progress;
  final Color primary, track, border;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .405;
    final brush = Paint()..style = PaintingStyle.stroke;
    canvas.drawCircle(
      center,
      size.shortestSide * .49,
      brush
        ..strokeWidth = 1
        ..color = border.withValues(alpha: .65),
    );
    canvas.drawCircle(
      center,
      radius,
      brush
        ..strokeWidth = 5
        ..color = track,
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        brush
          ..strokeCap = StrokeCap.round
          ..color = primary,
      );
    }
    final fill = Paint();
    for (final (index, color) in [
      (0, KayleoColors.protein),
      (1, KayleoColors.carbs),
      (2, KayleoColors.fat),
    ]) {
      final angle = -math.pi / 2 + index * 2 * math.pi / 3 + progress * .45;
      final dot =
          center +
          Offset(math.cos(angle), math.sin(angle)) * (size.shortestSide * .49);
      canvas.drawCircle(dot, 4, fill..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _BalanceRing oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.primary != primary ||
      oldDelegate.track != track ||
      oldDelegate.border != border;
}
