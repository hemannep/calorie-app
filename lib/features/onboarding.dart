import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/ui.dart';
import '../data/models.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.state});
  final AppState state;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0;
  bool saving = false;
  Timer? preparationTimer;
  int preparationTick = 0;
  final profile = BodyProfile();
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final age = TextEditingController(text: '28');
  final height = TextEditingController(text: '172');
  final weight = TextEditingController(text: '70');
  @override
  void initState() {
    super.initState();
    name.text = widget.state.profile.name;
    profile.name = widget.state.profile.name;
  }

  @override
  void dispose() {
    preparationTimer?.cancel();
    name.dispose();
    age.dispose();
    height.dispose();
    weight.dispose();
    super.dispose();
  }

  void next() {
    if (step == 4) {
      if (!form.currentState!.validate()) {
        return;
      }
      profile.name = name.text.trim().isEmpty ? 'Friend' : name.text.trim();
      profile.age = int.parse(age.text);
      profile.height = double.parse(height.text);
      profile.weight = double.parse(weight.text);
    }
    if (step == 5) {
      profile.calculateTargets();
      setState(() {
        step = 6;
        preparationTick = 0;
      });
      preparationTimer?.cancel();
      preparationTimer = Timer.periodic(const Duration(milliseconds: 100), (
        timer,
      ) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          preparationTick++;
          if (preparationTick >= 100) {
            timer.cancel();
            step = 7;
          }
        });
      });
      return;
    }
    if (step < 7) {
      setState(() => step++);
    } else {
      complete();
    }
  }

  void previous() {
    if (step == 7) {
      setState(() => step = 5);
    } else if (step > 0 && step != 6) {
      setState(() => step--);
    }
  }

  Future<void> complete({bool demo = false}) async {
    if (saving) {
      return;
    }
    setState(() => saving = true);
    await widget.state.completeOnboarding(
      demo ? BodyProfile() : profile,
      withDemo: demo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _OnboardingBackdrop()),
          SafeArea(
            child: Row(
              children: [
                if (wide) Expanded(child: _illustration(true)),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.all(wide ? 60 : KayleoSpacing.xl),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!wide) ...[
                              Row(
                                children: [
                                  if (step < 3)
                                    SizedBox(
                                      width: 48,
                                      child: step > 0
                                          ? IconButton(
                                              onPressed: saving
                                                  ? null
                                                  : previous,
                                              tooltip: 'Previous step',
                                              icon: Icon(
                                                Icons.arrow_back_rounded,
                                              ),
                                            )
                                          : null,
                                    ),
                                  Expanded(
                                    child: Align(
                                      alignment: step < 3
                                          ? Alignment.center
                                          : Alignment.centerLeft,
                                      child: const Brand(size: 30),
                                    ),
                                  ),
                                  if (step < 3) const SizedBox(width: 48),
                                ],
                              ),
                              const SizedBox(height: KayleoSpacing.lg),
                              if (step < 3)
                                ExcludeSemantics(
                                  child: SizedBox(
                                    height: 252,
                                    child: _illustration(false),
                                  ),
                                ),
                              const SizedBox(height: KayleoSpacing.xl),
                            ],
                            if (step >= 3 || wide) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      step < 3
                                          ? 'MEET KAYLEO'
                                          : 'MAKE IT YOURS',
                                      style: TextStyle(
                                        fontSize: 12,
                                        letterSpacing: 1.2,
                                        fontWeight: FontWeight.w800,
                                        color: context.kayleoPrimary,
                                      ),
                                    ),
                                  ),
                                  if (step > 0 && step != 6)
                                    IconButton(
                                      onPressed: saving ? null : previous,
                                      tooltip: 'Previous step',
                                      icon: Icon(
                                        Icons.arrow_back_rounded,
                                        size: 20,
                                      ),
                                    ),
                                  Semantics(
                                    label: 'Step ${step + 1} of 8',
                                    excludeSemantics: true,
                                    child: Text(
                                      '${step + 1} / 8',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: context.kayleoMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: KayleoSpacing.md),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: (step + 1) / 8,
                                  minHeight: 4,
                                  backgroundColor:
                                      context.kayleoSurfaces.border,
                                  color: context.kayleoPrimary,
                                ),
                              ),
                              const SizedBox(height: KayleoSpacing.card),
                            ],
                            AnimatedSwitcher(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 240),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(.025, .015),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: KeyedSubtree(
                                key: ValueKey(step),
                                child: _content(),
                              ),
                            ),
                            const SizedBox(height: KayleoSpacing.xxl),
                            if (step != 6)
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  key: const Key('onboarding-continue'),
                                  onPressed: saving ? null : next,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: lime,
                                    foregroundColor: forest,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          saving
                                              ? 'Preparing your space…'
                                              : step == 7
                                              ? 'Let’s start your day'
                                              : step == 0
                                              ? 'Get started'
                                              : 'Continue',
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      const SizedBox(width: KayleoSpacing.md),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: KayleoSpacing.md),
                            if (step < 3)
                              Center(
                                child: TextButton(
                                  key: const Key('explore-demo'),
                                  onPressed: saving
                                      ? null
                                      : () => complete(demo: true),
                                  child: Text(
                                    'Explore with sample data',
                                    style: TextStyle(
                                      color: context.kayleoMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: KayleoSpacing.card),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  color: context.kayleoMuted,
                                  size: 13,
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    'Your plan is always yours to adjust.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: context.kayleoMuted,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _illustration(bool wide) {
    final theme = Theme.of(context);
    final soft = theme.extension<KayleoSurfaces>()!.soft;
    return Container(
      color: wide ? soft.withValues(alpha: .3) : null,
      child: Stack(
        children: [
          if (wide) const Positioned(left: 48, top: 44, child: Brand(size: 34)),
          Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = wide
                    ? math.min(constraints.maxWidth - 72, 420.0)
                    : constraints.maxWidth;
                return ExcludeSemantics(
                  child: MediaQuery.withNoTextScaling(
                    child: SizedBox(
                      width: width,
                      height: wide ? 370 : 252,
                      child: _collage(step < 3 ? step : 0),
                    ),
                  ),
                );
              },
            ),
          ),
          if (wide)
            Positioned(
              left: 48,
              right: 48,
              bottom: 48,
              child: Text(
                'Your day, in balance.',
                style: theme.textTheme.titleLarge,
              ),
            ),
        ],
      ),
    );
  }

  Widget _photoCard(String image, double width, double height, double angle) =>
      Transform.rotate(
        angle: angle,
        child: Container(
          width: width,
          height: height,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Theme.of(context).extension<KayleoSurfaces>()!.card,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .08),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset('assets/images/$image.jpg', fit: BoxFit.cover),
          ),
        ),
      );

  Widget _collage(int intro) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      final scheme = Theme.of(context).colorScheme;
      final surface = Theme.of(context).extension<KayleoSurfaces>()!.card;
      if (intro == 0) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: width * .03,
              top: height * .22,
              child: _photoCard('burger', width * .42, height * .58, -.16),
            ),
            Positioned(
              right: width * .02,
              top: height * .12,
              child: _photoCard('pancakes', width * .40, height * .56, .15),
            ),
            Positioned(
              left: width * .23,
              top: height * .08,
              child: _photoCard('salad', width * .55, height * .80, -.04),
            ),
            Positioned(
              right: width * .10,
              bottom: 10,
              child: Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: lime,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.camera_alt_outlined, color: forest, size: 24),
              ),
            ),
          ],
        );
      }
      if (intro == 1) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: width * .08,
              top: height * .12,
              child: _photoCard('bowl', width * .62, height * .67, -.10),
            ),
            Positioned(
              right: width * .02,
              top: height * .06,
              child: _photoCard('breakfast', width * .40, height * .48, .12),
            ),
            Positioned(
              left: width * .10,
              right: width * .06,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .06),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 19,
                      backgroundColor: lime,
                      child: Icon(
                        Icons.mic_none_rounded,
                        color: forest,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(
                          18,
                          (i) => Container(
                            width: 3,
                            height: [12.0, 22.0, 34.0, 17.0, 28.0, 38.0][i % 6],
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(
                                alpha: i < 12 ? .9 : .3,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: width * .03,
            top: height * .10,
            child: _photoCard('momo', width * .48, height * .65, -.14),
          ),
          Positioned(
            right: width * .05,
            top: height * .10,
            child: _photoCard('curry', width * .56, height * .65, .11),
          ),
          Positioned(
            left: width * .04,
            right: width * .04,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .07),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Rice, curry and a side of greens',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: lime,
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      color: forest,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _content() {
    if (step == 6) return _preparingPlan();
    const titles = [
      'Snap it.\nKayleo gets it.',
      'Speak naturally.\nJust like you.',
      'Or type it.',
      'What brings\nyou here?',
      'About you.',
      'Find your\nrhythm.',
      '',
      'Your plan.\nYour pace.',
    ];
    const descriptions = [
      'Add a meal photo and review the details. Photo recognition is a preview in this prototype.',
      'Describe your meal with device voice input. You stay in control of the details.',
      'Start with the food you ate. Review portions, calories, and macros before adding.',
      'There’s no perfect goal. Choose what feels right for this chapter.',
      'We use these details to estimate your daily energy needs. You can always change your targets.',
      'Your routine helps us set a useful starting point. No workouts or wearables required.',
      '',
      'A practical starting point for your day. Every target is editable in Your space.',
    ];
    return Column(
      crossAxisAlignment: step < 3
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          titles[step],
          textAlign: step < 3 ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize:
                MediaQuery.sizeOf(context).width < 360 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20
                ? 32
                : 40,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.8,
            height: 1.15,
          ),
        ),
        const SizedBox(height: KayleoSpacing.page),
        Text(
          descriptions[step],
          textAlign: step < 3 ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: 14,
            height: 1.8,
            color: context.kayleoMuted,
          ),
        ),
        const SizedBox(height: 26),
        if (step < 3)
          Semantics(
            label: 'Introduction ${step + 1} of 3',
            excludeSemantics: true,
            child: Row(
              key: const Key('onboarding-intro-progress'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (i) => AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  width: i == step ? 20 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == step
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).extension<KayleoSurfaces>()!.border,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        if (step == 3) ...[
          for (final (goal, icon, sub) in [
            (
              'Feel healthier',
              Icons.spa_outlined,
              'Understand my food and build better habits',
            ),
            (
              'Lose weight',
              Icons.trending_down_rounded,
              'A gentle, sustainable starting point',
            ),
            (
              'Maintain weight',
              Icons.balance_rounded,
              'Find balance in my everyday meals',
            ),
            (
              'Build muscle',
              Icons.fitness_center_rounded,
              'Fuel my strength and recovery',
            ),
          ])
            _choice(
              goal,
              sub,
              icon,
              profile.goal == goal,
              () => setState(() => profile.goal = goal),
            ),
        ],
        if (step == 4)
          Form(
            key: form,
            child: Column(
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'What should we call you?',
                    hintText: 'Your first name',
                  ),
                  textCapitalization: TextCapitalization.words,
                  maxLength: 24,
                ),
                const SizedBox(height: 14),
                _adaptiveFields(
                  TextFormField(
                    controller: age,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Age'),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 18 || n > 100
                          ? 'Adults 18–100'
                          : null;
                    },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: profile.sex,
                    isExpanded: true,
                    style: TextStyle(fontSize: 14, color: context.kayleoText),
                    decoration: const InputDecoration(
                      labelText: 'Sex for calculation',
                    ),
                    items: ['Prefer not to say', 'Female', 'Male']
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(
                              v,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => profile.sex = v!,
                  ),
                ),
                const SizedBox(height: KayleoSpacing.lg),
                _adaptiveFields(
                  _numberField(height, 'Height (cm)', 100, 250),
                  _numberField(weight, 'Weight (kg)', 30, 300),
                ),
                const SizedBox(height: KayleoSpacing.lg),
                Text(
                  'This prototype provides general estimates for adults. If sex is unspecified, the formula uses a midpoint. It does not account for pregnancy or medical needs.',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.kayleoMuted,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        if (step == 5) ...[
          for (final (value, sub) in [
            ('Mostly sitting', 'Desk days, light movement'),
            ('Lightly active', 'Some walking, 1–3 workouts a week'),
            ('Moderately active', 'Regular movement, 3–5 workouts a week'),
            ('Very active', 'An active job or frequent training'),
          ])
            _choice(
              value,
              sub,
              Icons.directions_walk_rounded,
              profile.activity == value,
              () => setState(() => profile.activity = value),
            ),
          const SizedBox(height: KayleoSpacing.lg),
          Text(
            'How do you like to eat?',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: KayleoSpacing.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Everything', 'Vegetarian', 'Vegan', 'Pescatarian']
                .map(
                  (diet) => ChoiceChip(
                    label: Text(
                      diet,
                      style: TextStyle(
                        fontSize: 12,
                        color: profile.diet == diet
                            ? forest
                            : context.kayleoText,
                      ),
                    ),
                    selected: profile.diet == diet,
                    onSelected: (_) => setState(() => profile.diet = diet),
                    selectedColor: lime,
                    checkmarkColor: forest,
                    side: BorderSide(color: context.kayleoSurfaces.border),
                  ),
                )
                .toList(),
          ),
        ],
        if (step == 7) ...[
          Panel(
            color: context.kayleoSurfaces.soft,
            border: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tag(
                  'YOUR DAILY STARTING POINT',
                  color: Colors.white,
                  icon: Icons.spa_outlined,
                ),
                const SizedBox(height: KayleoSpacing.page),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    Text(
                      number(profile.calorieTarget),
                      style: TextStyle(
                        color: context.kayleoPrimary,
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(bottom: KayleoSpacing.sm),
                      child: Text(
                        'kcal / day',
                        style: TextStyle(color: context.kayleoPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: KayleoSpacing.card),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        constraints.maxWidth < 240 ||
                            MediaQuery.textScalerOf(context).scale(12) > 16
                        ? 1
                        : 3;
                    final width =
                        (constraints.maxWidth - 16 * (columns - 1)) / columns;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 20,
                      children: [
                        SizedBox(
                          width: width,
                          child: MacroBar(
                            'Protein',
                            0,
                            profile.proteinTarget,
                            KayleoColors.protein,
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: MacroBar(
                            'Carbs',
                            0,
                            profile.carbTarget,
                            orange,
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: MacroBar(
                            'Fat',
                            0,
                            profile.fatTarget,
                            KayleoColors.fat,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Built from your details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Resting energy and activity estimate: ${number(profile.maintenance)} kcal/day',
                ),
                const SizedBox(height: 8),
                Text('Goal: ${profile.goal} · Activity: ${profile.activity}'),
                const SizedBox(height: 8),
                Text(
                  'BMI ${profile.bmi.toStringAsFixed(1)} · ${profile.bmiCategory}',
                ),
                const SizedBox(height: 12),
                Text(
                  'BMI is a screening measure, not a diagnosis. Your calorie and macro targets are estimates you can adjust.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: context.kayleoMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _preparingPlan() {
    final progress = (preparationTick / 100).clamp(0.0, 1.0);
    final phase = preparationTick < 34
        ? 'Estimating daily energy from your measurements'
        : preparationTick < 68
        ? 'Accounting for your activity and goal'
        : 'Balancing calories and macros';
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: context.kayleoSurfaces.soft,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: context.kayleoPrimary,
              size: 34,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Preparing your personal plan',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: -1.4,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'We’re using your answers to calculate a useful starting point.',
            style: TextStyle(
              fontSize: 14,
              height: 1.7,
              color: context.kayleoMuted,
            ),
          ),
          const SizedBox(height: 38),
          LinearProgressIndicator(
            value: progress,
            minHeight: 9,
            borderRadius: BorderRadius.circular(12),
            backgroundColor: context.kayleoSurfaces.soft,
          ),
          const SizedBox(height: 14),
          Text(phase, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 24),
          for (final (index, label) in [
            (0, 'Your measurements'),
            (1, 'Your activity and goal'),
            (2, 'Daily nutrition targets'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(
                    preparationTick >= (index + 1) * 33
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: context.kayleoPrimary,
                    size: 21,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _adaptiveFields(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 360 ||
          MediaQuery.textScalerOf(context).scale(14) > 20) {
        return Column(
          children: [
            first,
            const SizedBox(height: KayleoSpacing.lg),
            second,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: KayleoSpacing.md),
          Expanded(child: second),
        ],
      );
    },
  );

  Widget _choice(
    String title,
    String sub,
    IconData icon,
    bool selected,
    VoidCallback action,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(KayleoSpacing.lg),
          decoration: BoxDecoration(
            color: selected
                ? context.kayleoSurfaces.soft
                : context.kayleoSurfaces.card,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? context.kayleoPrimary
                  : context.kayleoSurfaces.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? context.kayleoPrimary
                      : context.kayleoSurfaces.soft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: selected
                      ? Theme.of(context).colorScheme.onPrimary
                      : context.kayleoPrimary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.kayleoMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected
                    ? context.kayleoPrimary
                    : context.kayleoSurfaces.border,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _numberField(
    TextEditingController c,
    String label,
    double min,
    double max,
  ) => TextFormField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label),
    validator: (v) {
      final n = double.tryParse(v ?? '');
      return n == null || !n.isFinite || n < min || n > max
          ? '$min–$max'
          : null;
    },
  );
}

class _OnboardingBackdrop extends StatelessWidget {
  const _OnboardingBackdrop();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          context.kayleoBackground,
          context.kayleoSurfaces.soft.withValues(alpha: .18),
          context.kayleoBackground,
        ],
      ),
    ),
  );
}
