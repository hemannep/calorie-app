import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/milestones.dart';
import '../core/ui.dart';

final kayleoRouteObserver = RouteObserver<ModalRoute<dynamic>>();

Color badgeColor(String metric) => switch (metric) {
  'streak' => const Color(0xFFE6A052),
  'water' => const Color(0xFF7298D4),
  'protein' => const Color(0xFFDC737B),
  'saved' => const Color(0xFF9D8BCB),
  'days' => const Color(0xFF78A38C),
  _ => const Color(0xFFD4A16B),
};

IconData badgeIcon(String metric) => switch (metric) {
  'streak' => Icons.local_fire_department_rounded,
  'water' => Icons.water_drop_rounded,
  'protein' => Icons.restaurant_rounded,
  'saved' => Icons.bookmark_rounded,
  'days' => Icons.calendar_month_rounded,
  _ => Icons.ramen_dining_rounded,
};

String badgeRequirement(Milestone m) => switch (m.metric) {
  'streak' => 'Log food ${m.target} days in a row',
  'water' =>
    'Reach your water goal on ${m.target} ${m.target == 1 ? 'day' : 'days'}',
  'protein' =>
    'Reach your protein goal on ${m.target} ${m.target == 1 ? 'day' : 'days'}',
  'saved' => 'Save ${m.target} ${m.target == 1 ? 'meal' : 'meals'}',
  'days' => 'Log food on ${m.target} days',
  _ => 'Log ${m.target} ${m.target == 1 ? 'meal' : 'meals'}',
};

Future<void> openMilestones(BuildContext context, AppState state) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => MilestonesScreen(state: state)),
    );

/// Only presents on the home route, after a logging screen has closed.
class MilestoneCelebrationHost extends StatefulWidget {
  const MilestoneCelebrationHost({
    super.key,
    required this.state,
    required this.child,
  });
  final AppState state;
  final Widget child;
  @override
  State<MilestoneCelebrationHost> createState() =>
      _MilestoneCelebrationHostState();
}

class _MilestoneCelebrationHostState extends State<MilestoneCelebrationHost>
    with RouteAware {
  ModalRoute<dynamic>? _route;
  bool _scheduled = false, _showing = false;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_check);
    _check();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      kayleoRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) kayleoRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didUpdateWidget(covariant MilestoneCelebrationHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_check);
      widget.state.addListener(_check);
      _check();
    }
  }

  @override
  void didPopNext() => _check();

  void _check() {
    if (_scheduled || _showing || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scheduled = false;
      if (!mounted || _showing || !(_route?.isCurrent ?? false)) return;
      final state = widget.state;
      if (state.signedOut ||
          !state.onboarded ||
          state.preferences['Milestone celebrations'] != true) {
        return;
      }
      final pending = milestones
          .where(
            (m) =>
                state.milestoneUnlocks.containsKey(m.id) &&
                !state.celebratedMilestones.contains(m.id),
          )
          .toList();
      if (pending.isEmpty) return;
      _showing = true;
      state.celebratedMilestones.addAll(pending.map((m) => m.id));
      unawaited(state.persist());
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              MilestoneCelebrationScreen(state: state, earned: pending),
        ),
      );
      _showing = false;
      _check();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    widget.state.removeListener(_check);
    kayleoRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class StreakSummary extends StatelessWidget {
  const StreakSummary({super.key, required this.state, this.onTap});
  final AppState state;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final best = math.max(state.streak, state.milestoneCounts['streak'] ?? 0);
    return Panel(
      padding: 20,
      child: InkWell(
        onTap: onTap ?? () => openMilestones(context, state),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'A little, every day',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: context.kayleoMuted),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 12,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department_rounded,
                        size: 46,
                        color: badgeColor('streak'),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${state.streak}',
                            style: const TextStyle(
                              fontSize: 34,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'day streak',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.kayleoMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$best',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'personal best',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.kayleoMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _StreakWeek(state: state),
          ],
        ),
      ),
    );
  }
}

class AchievementOverview extends StatelessWidget {
  const AchievementOverview({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final wideText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
      final width = wideText ? c.maxWidth : (c.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: width,
            child: Panel(
              padding: 18,
              child: InkWell(
                onTap: () => openMilestones(context, state),
                child: Column(
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      size: 48,
                      color: badgeColor('streak'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${state.streak}',
                      style: const TextStyle(
                        fontSize: 32,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Day streak',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 15),
                    _StreakWeek(state: state, dotSize: 16),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: width,
            child: Panel(
              padding: 18,
              child: InkWell(
                key: const Key('open-milestones'),
                onTap: () => openMilestones(context, state),
                child: Column(
                  children: [
                    const Icon(
                      Icons.workspace_premium_rounded,
                      size: 48,
                      color: Color(0xFF9D8BCB),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${state.milestoneUnlocks.length}',
                      style: const TextStyle(
                        fontSize: 32,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Milestones earned',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 17),
                    Text(
                      'View your collection',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.kayleoMuted,
                      ),
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value:
                            state.milestoneUnlocks.length / milestones.length,
                        minHeight: 5,
                        color: const Color(0xFF9D8BCB),
                        backgroundColor: context.kayleoSurfaces.soft,
                      ),
                    ),
                    const SizedBox(height: 5),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _StreakWeek extends StatelessWidget {
  const _StreakWeek({required this.state, this.dotSize = 27});
  final AppState state;
  final double dotSize;
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: today.weekday - 1));
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Column(
              children: [
                Text(
                  ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i],
                  style: TextStyle(
                    fontSize: dotSize < 20 ? 8 : 10,
                    color: context.kayleoMuted,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        state.mealsFor(start.add(Duration(days: i))).isNotEmpty
                        ? badgeColor('streak')
                        : context.kayleoSurfaces.soft,
                  ),
                  child: state.mealsFor(start.add(Duration(days: i))).isNotEmpty
                      ? Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: dotSize * .63,
                        )
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class MilestoneBadge extends StatelessWidget {
  const MilestoneBadge({
    super.key,
    required this.milestone,
    required this.earned,
    this.size = 92,
  });
  final Milestone milestone;
  final bool earned;
  final double size;
  @override
  Widget build(BuildContext context) {
    final color = earned
        ? badgeColor(milestone.metric)
        : context.kayleoMuted.withValues(alpha: .33);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _BadgePainter(color, earned),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                badgeIcon(milestone.metric),
                size: size * .26,
                color: earned ? Colors.white : color,
              ),
              const SizedBox(height: 3),
              Text(
                '${milestone.target}',
                style: TextStyle(
                  fontSize: size * .23,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: earned ? Colors.white : color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  _BadgePainter(this.color, this.earned);
  final Color color;
  final bool earned;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = -math.pi / 2 + i * math.pi / 3;
      final point = Offset(
        size.width / 2 + math.cos(angle) * size.width * .46,
        size.height / 2 + math.sin(angle) * size.height * .46,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    if (earned) canvas.drawShadow(path, color.withValues(alpha: .28), 8, false);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: earned
              ? [
                  Color.lerp(color, Colors.white, .25)!,
                  color,
                  Color.lerp(color, Colors.black, .12)!,
                ]
              : [color.withValues(alpha: .12), color.withValues(alpha: .06)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: earned ? .5 : .25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _BadgePainter old) =>
      old.color != color || old.earned != earned;
}

class MilestonesScreen extends StatefulWidget {
  const MilestonesScreen({super.key, required this.state});
  final AppState state;
  @override
  State<MilestonesScreen> createState() => _MilestonesScreenState();
}

class _MilestonesScreenState extends State<MilestonesScreen> {
  final _overviewKey = GlobalKey();
  String filter = 'All';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final state = widget.state;
      final counts = state.milestoneCounts;
      final visible = milestones
          .where(
            (m) => switch (filter) {
              'Earned' => state.milestoneUnlocks.containsKey(m.id),
              'Streaks' => m.metric == 'streak' || m.metric == 'days',
              'Food' =>
                m.metric == 'meals' ||
                    m.metric == 'protein' ||
                    m.metric == 'saved',
              'Water' => m.metric == 'water',
              _ => true,
            },
          )
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: const Text('Milestones'),
          actions: [
            IconButton(
              tooltip: 'Share your progress',
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () => _share(
                context,
                '${state.milestoneUnlocks.length} Kayleo milestones earned and a ${state.streak}-day streak. A little, every day.',
                boundaryKey: _overviewKey,
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Small steps. Real progress.',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A collection of the habits you’re building.',
                style: TextStyle(color: context.kayleoMuted, fontSize: 13),
              ),
              const SizedBox(height: 24),
              RepaintBoundary(
                key: _overviewKey,
                child: Container(
                  color: context.kayleoBackground,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StreakSummary(state: state, onTap: () {}),
                      const SizedBox(height: 16),
                      Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Your collection',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                Text(
                                  '${state.milestoneUnlocks.length}/${milestones.length}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value:
                                    state.milestoneUnlocks.length / milestones.length,
                                minHeight: 6,
                                color: context.kayleoPrimary,
                                backgroundColor: context.kayleoSurfaces.soft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final title in [
                      'All',
                      'Earned',
                      'Streaks',
                      'Food',
                      'Water',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(title),
                          selected: filter == title,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => filter = title),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (visible.isEmpty)
                const EmptyState(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Your first badge is waiting',
                  subtitle: 'Log a meal to begin your collection.',
                ),
              LayoutBuilder(
                builder: (context, c) {
                  final columns =
                      MediaQuery.textScalerOf(context).scale(1) > 1.3
                      ? 2
                      : c.maxWidth >= 600
                      ? 4
                      : 3;
                  final width = (c.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 26,
                    children: [
                      for (final m in visible)
                        SizedBox(
                          width: width,
                          child: InkWell(
                            key: Key('milestone-${m.id}'),
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => _detail(
                              context,
                              m,
                              counts[m.metric] ?? 0,
                              state,
                            ),
                            child: Column(
                              children: [
                                MilestoneBadge(
                                  milestone: m,
                                  earned: state.milestoneUnlocks.containsKey(
                                    m.id,
                                  ),
                                  size: width.clamp(70, 110),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  m.title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  state.milestoneUnlocks.containsKey(m.id)
                                      ? 'Earned'
                                      : '${(counts[m.metric] ?? 0).clamp(0, m.target)} / ${m.target}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: context.kayleoMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 30),
              Text(
                'Your own pace counts. Sample records don’t earn badges.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: context.kayleoMuted),
              ),
            ],
          ),
        ),
      );
    },
  );

  void _detail(BuildContext context, Milestone m, int count, AppState state) {
    final earned = state.milestoneUnlocks.containsKey(m.id);
    openSheet(
      context,
      _MilestoneDetailSheet(
        milestone: m,
        earned: earned,
        count: count,
        state: state,
      ),
    );
  }
}

class _MilestoneDetailSheet extends StatefulWidget {
  const _MilestoneDetailSheet({
    required this.milestone,
    required this.earned,
    required this.count,
    required this.state,
  });
  final Milestone milestone;
  final bool earned;
  final int count;
  final AppState state;

  @override
  State<_MilestoneDetailSheet> createState() => _MilestoneDetailSheetState();
}

class _MilestoneDetailSheetState extends State<_MilestoneDetailSheet> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.milestone;
    final earned = widget.earned;
    final state = widget.state;
    final earnedDateStr = earned && state.milestoneUnlocks.containsKey(m.id)
        ? DateFormat.yMMMd().format(DateTime.parse(state.milestoneUnlocks[m.id]!))
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            key: _cardKey,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: BoxDecoration(
                color: context.kayleoSurfaces.card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: context.kayleoMuted.withValues(alpha: .15),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Brand(size: 20),
                    ],
                  ),
                  const SizedBox(height: 16),
                  MilestoneBadge(milestone: m, earned: earned, size: 140),
                  const SizedBox(height: 18),
                  Text(
                    m.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    badgeRequirement(m),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.kayleoMuted),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    earned
                        ? m.compliment
                        : '${widget.count.clamp(0, m.target)} of ${m.target} completed',
                    textAlign: TextAlign.center,
                  ),
                  if (earnedDateStr != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Earned $earnedDateStr',
                      style: TextStyle(fontSize: 11, color: context.kayleoMuted),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (earned) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _sharing
                  ? null
                  : () async {
                      setState(() => _sharing = true);
                      try {
                        await _share(
                          context,
                          'I earned “${m.title}” in Kayleo. ${badgeRequirement(m)}.',
                          boundaryKey: _cardKey,
                          milestone: m,
                          earnedDate: earnedDateStr,
                        );
                      } finally {
                        if (mounted) setState(() => _sharing = false);
                      }
                    },
              icon: _sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded),
              label: Text(_sharing ? 'Sharing...' : 'Share milestone'),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _share(
  BuildContext context,
  String text, {
  GlobalKey? boundaryKey,
  Milestone? milestone,
  String? earnedDate,
}) async {
  final box = context.findRenderObject() as RenderBox?;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  try {
    Uint8List? imageBytes;
    if (boundaryKey != null) {
      try {
        final boundary = boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary != null && boundary.attached) {
          final image = await boundary.toImage(pixelRatio: 3.0);
          final byteData =
              await image.toByteData(format: ui.ImageByteFormat.png);
          imageBytes = byteData?.buffer.asUint8List();
        }
      } catch (e) {
        debugPrint('Could not capture boundary: $e');
      }
    }

    if (imageBytes == null && milestone != null) {
      try {
        imageBytes = await _generateMilestoneImage(
          milestone: milestone,
          earnedDate: earnedDate,
          isDark: isDark,
        );
      } catch (e) {
        debugPrint('Could not generate milestone image: $e');
      }
    }

    if (imageBytes != null && imageBytes.isNotEmpty) {
      final fileName = milestone != null
          ? 'kayleo-milestone-${milestone.id}.png'
          : 'kayleo-milestone.png';
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                imageBytes,
                mimeType: 'image/png',
              ),
            ],
            fileNameOverrides: [fileName],
            text: text,
            title: milestone != null
                ? 'Kayleo Milestone: ${milestone.title}'
                : 'Kayleo Milestone',
            sharePositionOrigin: (box != null && box.attached)
                ? box.localToGlobal(Offset.zero) & box.size
                : null,
          ),
        );
        return;
      } catch (e) {
        debugPrint('File sharing failed, falling back to text: $e');
      }
    }

    await SharePlus.instance.share(
      ShareParams(
        text: text,
        sharePositionOrigin: (box != null && box.attached)
            ? box.localToGlobal(Offset.zero) & box.size
            : null,
      ),
    );
  } catch (_) {
    if (context.mounted) toast(context, 'Could not open sharing. Try again.');
  }
}

Future<Uint8List> _generateMilestoneImage({
  required Milestone milestone,
  String? earnedDate,
  bool isDark = true,
}) async {
  final recorder = ui.PictureRecorder();
  const width = 680.0;
  const height = 880.0;
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));

  final color = badgeColor(milestone.metric);

  final bgPaint = Paint()
    ..color = isDark ? const Color(0xFF16181B) : const Color(0xFFF7F8FA);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, width, height),
      const Radius.circular(36),
    ),
    bgPaint,
  );

  final glowPaint = Paint()
    ..shader = ui.Gradient.radial(
      const Offset(width / 2, 330),
      260,
      [color.withValues(alpha: isDark ? .28 : .18), Colors.transparent],
    );
  canvas.drawCircle(const Offset(width / 2, 330), 260, glowPaint);

  final borderPaint = Paint()
    ..color = isDark
        ? Colors.white.withValues(alpha: .08)
        : Colors.black.withValues(alpha: .06)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(16, 16, width - 32, height - 32),
      const Radius.circular(32),
    ),
    borderPaint,
  );

  final brandPainter = TextPainter(
    text: TextSpan(
      children: [
        TextSpan(
          text: 'kayleo',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1E2124),
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.2,
          ),
        ),
        const TextSpan(
          text: '.',
          style: TextStyle(
            color: Color(0xFFC7F33B),
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  brandPainter.paint(canvas, Offset((width - brandPainter.width) / 2, 54));

  final labelPainter = TextPainter(
    text: TextSpan(
      text: 'MILESTONE UNLOCKED',
      style: TextStyle(
        color: color,
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 2.0,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  labelPainter.paint(canvas, Offset((width - labelPainter.width) / 2, 104));

  const badgeSize = 200.0;
  canvas.save();
  canvas.translate((width - badgeSize) / 2, 155);

  final path = Path();
  for (var i = 0; i < 6; i++) {
    final angle = -math.pi / 2 + i * math.pi / 3;
    final point = Offset(
      badgeSize / 2 + math.cos(angle) * badgeSize * .46,
      badgeSize / 2 + math.sin(angle) * badgeSize * .46,
    );
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  path.close();

  canvas.drawShadow(path, color.withValues(alpha: .35), 14, false);

  canvas.drawPath(
    path,
    Paint()
      ..shader = LinearGradient(
        colors: [
          Color.lerp(color, Colors.white, .25)!,
          color,
          Color.lerp(color, Colors.black, .12)!,
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(const Rect.fromLTWH(0, 0, badgeSize, badgeSize)),
  );

  canvas.drawPath(
    path,
    Paint()
      ..color = color.withValues(alpha: .5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );

  final icon = badgeIcon(milestone.metric);
  final iconPainter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: badgeSize * .28,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  iconPainter.paint(
    canvas,
    Offset((badgeSize - iconPainter.width) / 2, badgeSize * .24),
  );

  final numPainter = TextPainter(
    text: TextSpan(
      text: '${milestone.target}',
      style: const TextStyle(
        fontSize: badgeSize * .25,
        fontWeight: FontWeight.w800,
        color: Colors.white,
        height: 1,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  numPainter.paint(
    canvas,
    Offset((badgeSize - numPainter.width) / 2, badgeSize * .55),
  );

  canvas.restore();

  final titlePainter = TextPainter(
    text: TextSpan(
      text: milestone.title,
      style: TextStyle(
        color: isDark ? Colors.white : const Color(0xFF1E2124),
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -.8,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: ui.TextDirection.ltr,
  )..layout(maxWidth: width - 80);
  titlePainter.paint(canvas, Offset((width - titlePainter.width) / 2, 395));

  final reqPainter = TextPainter(
    text: TextSpan(
      text: badgeRequirement(milestone),
      style: TextStyle(
        color: isDark ? const Color(0xFF9EA3AE) : const Color(0xFF6B7280),
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: ui.TextDirection.ltr,
  )..layout(maxWidth: width - 80);
  reqPainter.paint(canvas, Offset((width - reqPainter.width) / 2, 452));

  final compPainter = TextPainter(
    text: TextSpan(
      text: milestone.compliment,
      style: TextStyle(
        color: isDark ? const Color(0xFFD1D5DB) : const Color(0xFF374151),
        fontSize: 17,
        height: 1.5,
        fontWeight: FontWeight.w500,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: ui.TextDirection.ltr,
  )..layout(maxWidth: width - 100);
  compPainter.paint(canvas, Offset((width - compPainter.width) / 2, 510));

  if (earnedDate != null && earnedDate.isNotEmpty) {
    final datePainter = TextPainter(
      text: TextSpan(
        text: 'Earned $earnedDate',
        style: TextStyle(
          color: isDark ? const Color(0xFF9EA3AE) : const Color(0xFF6B7280),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    )..layout();
    datePainter.paint(canvas, Offset((width - datePainter.width) / 2, 720));
  }

  final footerPainter = TextPainter(
    text: TextSpan(
      text: 'A little, every day.',
      style: TextStyle(
        color: isDark ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF),
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: .5,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  footerPainter.paint(canvas, Offset((width - footerPainter.width) / 2, 790));

  final picture = recorder.endRecording();
  final image = await picture.toImage(width.toInt(), height.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

class MilestoneCelebrationScreen extends StatefulWidget {
  const MilestoneCelebrationScreen({
    super.key,
    required this.state,
    required this.earned,
  });
  final AppState state;
  final List<Milestone> earned;

  @override
  State<MilestoneCelebrationScreen> createState() =>
      _MilestoneCelebrationScreenState();
}

class _MilestoneCelebrationScreenState
    extends State<MilestoneCelebrationScreen> {
  final _shareCardKey = GlobalKey();
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.earned.last;
    final color = badgeColor(m.metric);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final state = widget.state;
    final earned = widget.earned;
    final earnedDateStr = state.milestoneUnlocks.containsKey(m.id)
        ? DateFormat.yMMMd().format(DateTime.parse(state.milestoneUnlocks[m.id]!))
        : null;

    return Scaffold(
      key: const Key('milestone-celebration'),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                color.withValues(alpha: .22),
                context.kayleoBackground,
              ),
              context.kayleoBackground,
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 1600),
                    builder: (_, value, _) =>
                        CustomPaint(painter: _ConfettiPainter(value, color)),
                  ),
                ),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton.filledTonal(
                        tooltip: 'Close celebration',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                    const SizedBox(height: 28),
                    RepaintBoundary(
                      key: _shareCardKey,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                        decoration: BoxDecoration(
                          color: context.kayleoSurfaces.card,
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: context.kayleoMuted.withValues(alpha: .15),
                          ),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Brand(size: 22),
                              ],
                            ),
                            const SizedBox(height: 20),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: reduceMotion ? 1 : .7, end: 1),
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 650),
                              curve: Curves.easeOutBack,
                              builder: (_, scale, child) =>
                                  Transform.scale(scale: scale, child: child),
                              child: MilestoneBadge(
                                milestone: m,
                                earned: true,
                                size: 190,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              earned.length == 1
                                  ? 'MILESTONE UNLOCKED'
                                  : '${earned.length} MILESTONES UNLOCKED',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 1.8,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              m.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.9,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              badgeRequirement(m),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: context.kayleoMuted,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              m.compliment,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14, height: 1.6),
                            ),
                            if (earned.length > 1) ...[
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                children: earned
                                    .take(earned.length - 1)
                                    .map((badge) => Tag(badge.title))
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _sharing
                            ? null
                            : () async {
                                setState(() => _sharing = true);
                                try {
                                  await _share(
                                    context,
                                    'I earned “${m.title}” in Kayleo. ${badgeRequirement(m)}.',
                                    boundaryKey: _shareCardKey,
                                    milestone: m,
                                    earnedDate: earnedDateStr,
                                  );
                                } finally {
                                  if (mounted) setState(() => _sharing = false);
                                }
                              },
                        icon: _sharing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.ios_share_rounded, size: 19),
                        label: Text(
                          _sharing
                              ? 'Sharing milestone...'
                              : 'Share your milestone',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context)
                            .pushReplacement<void, void>(
                              MaterialPageRoute(
                                builder: (_) => MilestonesScreen(state: state),
                              ),
                            ),
                        child: const Text('View all milestones'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        state.preferences['Milestone celebrations'] = false;
                        unawaited(state.persist());
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Turn off celebrations',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.progress, this.color);
  final double progress;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(29);
    for (var i = 0; i < 36; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height * .6 + progress * 80;
      final paint = Paint()
        ..color = [
          color,
          KayleoColors.fat,
          KayleoColors.carbs,
        ][i % 3].withValues(alpha: .36 * (1 - progress * .5));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(random.nextDouble() * math.pi + progress);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-2, -4, 4, 8),
          const Radius.circular(1),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) =>
      old.progress != progress || old.color != color;
}
