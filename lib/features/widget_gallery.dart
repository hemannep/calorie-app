import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/ui.dart';
import '../services/home_widget_service.dart';

class WidgetGalleryScreen extends StatelessWidget {
  const WidgetGalleryScreen({super.key, required this.state});
  final AppState state;

  static const widgets = [
    (
      'calories',
      'Kayleo Calories',
      '2 × 2',
      'Today’s calories and a shortcut to your food camera.',
    ),
    (
      'barcode',
      'Kayleo Barcode',
      '2 × 2',
      'Scan a food label straight from your home screen.',
    ),
    (
      'streak',
      'Kayleo Streak',
      '2 × 2',
      'Your daily rhythm, with a week of check-ins.',
    ),
    (
      'rings',
      'Kayleo Nutrition',
      '4 × 2',
      'Calories, three macros, and scan or voice logging.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Home screen widgets'),
      actions: [
        IconButton(
          tooltip: 'How to add widgets',
          onPressed: () => _help(context),
          icon: const Icon(Icons.help_outline_rounded),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Your day, at a glance.',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Four small ways to keep Kayleo close.',
          style: TextStyle(color: context.kayleoMuted, fontSize: 13),
        ),
        const SizedBox(height: 24),
        for (final w in widgets) ...[
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        w.$2,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Tag(w.$3),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: w.$1 == 'rings' ? 336 : 172,
                    ),
                    child: AspectRatio(
                      aspectRatio: w.$1 == 'rings' ? 2.1 : 1,
                      child: KayleoWidgetPreview(
                        kind: w.$1,
                        streak: state.streak > 0 ? state.streak : 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  w.$4,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.kayleoMuted,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final requested = await HomeWidgetService.instance
                          .requestPin(w.$1);
                      if (context.mounted && !requested) _help(context);
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add to home screen'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    ),
  );

  void _help(BuildContext context) => openSheet(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add a Kayleo widget',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 22),
        const Text('Android', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Touch and hold an empty area on your home screen. Choose Widgets, find Kayleo, then drag your favorite widget into place.',
        ),
        const SizedBox(height: 20),
        const Text('iPhone', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Touch and hold your home screen. Tap Edit, then Add Widget. Search for Kayleo, choose a widget, and tap Add Widget.',
        ),
        const SizedBox(height: 20),
        Text(
          'Open Kayleo and sign in to show your daily totals. The previews above use example data.',
          style: TextStyle(fontSize: 12, color: context.kayleoMuted),
        ),
      ],
    ),
  );
}

/// Sample cards mirror the native widgets without relying on live account data.
class KayleoWidgetPreview extends StatelessWidget {
  const KayleoWidgetPreview({
    super.key,
    required this.kind,
    this.streak,
  });

  final String kind;
  final int? streak;

  @override
  Widget build(BuildContext context) => FittedBox(
    child: Container(
      width: kind == 'rings' ? 336 : 160,
      height: 160,
      padding: kind == 'streak' ? EdgeInsets.zero : const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFAF4),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFE2E6DC)),
      ),
      child: kind == 'streak'
          ? ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: SizedBox(
                width: 160,
                height: 160,
                child: CustomPaint(
                  painter: _StreakArtworkPainter(streak: streak ?? 2),
                ),
              ),
            )
          : DefaultTextStyle(
              style: const TextStyle(fontFamily: 'Manrope', color: Color(0xFF163E2D)),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        kind == 'rings' ? 'Kayleo Calories' : 'Kayleo',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Text(
                        switch (kind) {
                          'barcode' => 'Barcode',
                          'rings' => 'Today',
                          _ => 'Calories',
                        },
                        style: const TextStyle(fontSize: 9, color: Color(0xFF626E64)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Expanded(
                    child: switch (kind) {
                      'barcode' => Column(
                        children: [
                          const Expanded(
                            child: Center(
                              child: CustomPaint(
                                size: Size(55, 55),
                                painter: _BarcodePreviewPainter(),
                              ),
                            ),
                          ),
                          const Text(
                            'Food labels, faster',
                            style: TextStyle(fontSize: 9, color: Color(0xFF626E64)),
                          ),
                          const SizedBox(height: 8),
                          _button('Scan barcode', null),
                        ],
                      ),
                      'rings' => Row(
                        children: [
                          _ring(112),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _macro(
                                  'Protein left',
                                  '38g',
                                  KayleoColors.protein,
                                  .71,
                                ),
                                const SizedBox(height: 9),
                                _macro('Carbs left', '106g', KayleoColors.carbs, .58),
                                const SizedBox(height: 9),
                                _macro('Fat left', '26g', KayleoColors.fat, .63),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 64,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _action(Icons.camera_alt_outlined, 'Scan food'),
                                const SizedBox(height: 6),
                                _action(Icons.qr_code_scanner_rounded, 'Barcode'),
                                const SizedBox(height: 4),
                                _action(Icons.mic_none_rounded, 'Voice'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      _ => Column(
                        children: [
                          Expanded(child: Center(child: _ring(87))),
                          const SizedBox(height: 5),
                          _button('Log your food', Icons.add_rounded),
                        ],
                      ),
                    },
                  ),
                ],
              ),
            ),
    ),
  );

  Widget _ring(double size) => KayleoRing(
    size: size,
    progress: .67,
    segmented: true,
    stroke: 7,
    highlight: false,
    color: const Color(0xFF163E2D),
    track: const Color(0xFFE4EBDD),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '720',
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Calories left',
          style: TextStyle(fontSize: 8, color: Color(0xFF626E64)),
        ),
      ],
    ),
  );
  Widget _button(String title, IconData? icon) => Container(
    height: 28,
    decoration: BoxDecoration(
      color: KayleoColors.lime,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: KayleoColors.forest),
          const SizedBox(width: 4),
        ],
        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: KayleoColors.forest,
          ),
        ),
      ],
    ),
  );
  Widget _macro(String title, String value, Color color, double progress) =>
      Row(
        children: [
          KayleoRing(
            size: 26,
            stroke: 3,
            progress: progress,
            color: color,
            track: const Color(0xFFE4EBDD),
            highlight: false,
            child: const SizedBox.shrink(),
          ),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.1,
                  color: KayleoColors.forest,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  fontSize: 8,
                  color: color,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      );
  Widget _action(IconData icon, String title) => Container(
    height: 35,
    width: double.infinity,
    decoration: BoxDecoration(
      color: const Color(0xFFE4EBDD),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 17, color: const Color(0xFF163E2D)),
        const SizedBox(width: 3),
        Text(
          title,
          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

}

class _BarcodePreviewPainter extends CustomPainter {
  const _BarcodePreviewPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 55, size.height / 55);
    final paint = Paint()
      ..color = KayleoColors.forest
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (final x in [4.0, 51.0]) {
      for (final y in [9.0, 46.0]) {
        final dx = x == 4 ? 7.0 : -7.0;
        final dy = y == 9 ? 7.0 : -7.0;
        canvas.drawPath(
          Path()
            ..moveTo(x, y + dy)
            ..lineTo(x, y)
            ..lineTo(x + dx, y),
          paint,
        );
      }
    }
    paint.strokeCap = StrokeCap.butt;
    for (final x in [14.0, 19.0, 24.0, 30.0, 36.0, 41.0]) {
      paint.strokeWidth = x == 19 || x == 30 ? 3 : 1.7;
      canvas.drawLine(Offset(x, 18), Offset(x, 37), paint);
    }
  }

  @override
  bool shouldRepaint(_BarcodePreviewPainter oldDelegate) => false;
}

class _StreakArtworkPainter extends CustomPainter {
  const _StreakArtworkPainter({required this.streak});
  final int streak;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 600, size.height / 600);

    const background = Color(0xFFFCFAF4);

    final outerFlame = Path()
      ..moveTo(284, 84)
      ..cubicTo(350, 108, 380, 166, 370, 215)
      ..cubicTo(398, 198, 403, 173, 400, 156)
      ..cubicTo(461, 219, 469, 302, 429, 361)
      ..cubicTo(401, 407, 347, 432, 293, 422)
      ..cubicTo(217, 418, 168, 363, 174, 296)
      ..cubicTo(178, 250, 201, 218, 224, 190)
      ..cubicTo(217, 229, 235, 237, 246, 244)
      ..cubicTo(276, 193, 301, 143, 284, 84)
      ..close();

    final innerFlame = Path()
      ..moveTo(305, 225)
      ..cubicTo(332, 253, 337, 273, 331, 292)
      ..cubicTo(350, 282, 359, 270, 359, 258)
      ..cubicTo(392, 301, 385, 355, 354, 377)
      ..cubicTo(322, 398, 276, 394, 253, 363)
      ..cubicTo(225, 326, 252, 290, 274, 272)
      ..cubicTo(271, 294, 278, 305, 287, 310)
      ..cubicTo(303, 281, 312, 257, 305, 225)
      ..close();

    final outerPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFB530), Color(0xFFEF8044)],
      ).createShader(const Rect.fromLTRB(0, 80, 600, 440));
    canvas.drawPath(outerFlame, outerPaint);

    final innerPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFEEA4), Color(0xFFFFCC6F)],
      ).createShader(const Rect.fromLTRB(0, 80, 600, 440));
    canvas.drawPath(innerFlame, innerPaint);

    final starPaint = Paint()..color = const Color(0xFFFFD696);
    Path star(double x, double y, double radius) {
      final p = Path();
      p.moveTo(x, y - radius);
      p.lineTo(x + radius * 0.3, y - radius * 0.3);
      p.lineTo(x + radius, y);
      p.lineTo(x + radius * 0.3, y + radius * 0.3);
      p.lineTo(x, y + radius);
      p.lineTo(x - radius * 0.3, y + radius * 0.3);
      p.lineTo(x - radius, y);
      p.lineTo(x - radius * 0.3, y - radius * 0.3);
      p.close();
      return p;
    }

    canvas.drawPath(star(124, 161, 26), starPaint);
    canvas.drawPath(star(466, 117, 32), starPaint);
    canvas.drawPath(star(119, 289, 12), starPaint);

    final text = '$streak';
    final fontSize = streak < 100 ? 204.0 : 156.0;

    final strokeBg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 22
      ..color = background;

    final strokeOrange = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 10
      ..color = const Color(0xFFEFAB77);

    final fillBg = Paint()
      ..style = PaintingStyle.fill
      ..color = background;

    for (final paint in [strokeBg, strokeOrange, fillBg]) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            fontFamily: 'Manrope',
            foreground: paint,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final baseline = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      tp.paint(canvas, Offset(300 - tp.width / 2, 493 - baseline));
    }

    final kayleoPainter = TextPainter(
      text: const TextSpan(
        text: 'Kayleo',
        style: TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.bold,
          fontFamily: 'Manrope',
          color: Color(0xFF5B4F42),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final kayleoBaseline = kayleoPainter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    kayleoPainter.paint(canvas, Offset(300 - kayleoPainter.width / 2, 558 - kayleoBaseline));
  }

  @override
  bool shouldRepaint(_StreakArtworkPainter oldDelegate) => oldDelegate.streak != streak;
}

