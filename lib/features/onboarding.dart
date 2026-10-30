import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/ui.dart';
import '../data/models.dart';
import '../services/calorie_plan_service.dart';
import 'onboarding_plan_preparation.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.state,
    this.caloriePlanService,
  });
  final AppState state;
  final CaloriePlanService? caloriePlanService;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  static const _totalSteps = 9;
  int step = 0, direction = 1;
  bool saving = false,
      calculating = false,
      changingStep = false,
      exiting = false;
  bool aiPlanApplied = false;
  String aiPlanExplanation = '';
  final profile = BodyProfile();
  final form = GlobalKey<FormState>();
  final scroll = ScrollController();
  final name = TextEditingController();
  final age = TextEditingController(text: '28');
  final height = TextEditingController(text: '172');
  final heightFeet = TextEditingController(text: '5');
  final heightInches = TextEditingController(text: '8');
  final weight = TextEditingController(text: '70');
  final targetWeight = TextEditingController(text: '65');
  bool heightInMetric = true;
  late final AnimationController page;
  late final CaloriePlanService caloriePlanService;
  late final bool ownsCaloriePlanService;

  @override
  void initState() {
    super.initState();
    name.text = widget.state.profile.name;
    profile.name = widget.state.profile.name;
    ownsCaloriePlanService = widget.caloriePlanService == null;
    caloriePlanService = widget.caloriePlanService ?? CaloriePlanService();
    page = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 110),
    );
  }

  @override
  void dispose() {
    page.dispose();
    scroll.dispose();
    name.dispose();
    age.dispose();
    height.dispose();
    heightFeet.dispose();
    heightInches.dispose();
    weight.dispose();
    targetWeight.dispose();
    if (ownsCaloriePlanService) caloriePlanService.dispose();
    super.dispose();
  }

  Future<void> goTo(int nextStep) async {
    if (saving || changingStep || step == nextStep) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    setState(() {
      changingStep = true;
      exiting = true;
      direction = step == 7 && nextStep == 8
          ? 0
          : nextStep > step
          ? 1
          : -1;
    });
    if (!reduceMotion) await page.reverse();
    if (!mounted) return;
    setState(() {
      step = nextStep;
      exiting = false;
    });
    if (scroll.hasClients) scroll.jumpTo(0);
    if (reduceMotion) {
      page.value = 1;
    } else {
      await page.forward();
    }
    if (mounted) setState(() => changingStep = false);
  }

  Future<void> next() async {
    if (saving || calculating || changingStep) return;
    if (step == 4) {
      if (!form.currentState!.validate()) return;
      profile
        ..name = name.text.trim().isEmpty ? 'Friend' : name.text.trim()
        ..age = int.parse(age.text.trim())
        ..height = _heightInCentimeters()
        ..weight = double.parse(weight.text.trim())
        ..targetWeight = profile.goal == 'Lose weight'
            ? double.parse(targetWeight.text.trim())
            : null;
    }
    if (step == 6) {
      setState(() => calculating = true);
      final result = await caloriePlanService.calculate(profile);
      if (!mounted) return;
      setState(() {
        calculating = false;
        aiPlanApplied = result.usedGemini;
        aiPlanExplanation = result.explanation;
      });
    }
    if (step == 8) {
      complete();
    } else {
      goTo(step + 1);
    }
  }

  void previous() {
    if (step > 0 && step != 7) goTo(step == 8 ? 6 : step - 1);
  }

  Future<void> complete({bool demo = false}) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.state.completeOnboarding(
        demo ? BodyProfile() : profile,
        withDemo: demo,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: LocalizedText('Could not save your plan. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    return Scaffold(
      body: Row(
        children: [
          if (wide)
            SizedBox(
              width: math.min(MediaQuery.sizeOf(context).width * .4, 520),
              child: const _OnboardingIdentity(),
            ),
          Expanded(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: Column(
                    children: [
                      _navigation(),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) =>
                              SingleChildScrollView(
                                controller: scroll,
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  16,
                                  24,
                                  24,
                                ),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: math.max(
                                      0,
                                      constraints.maxHeight - 40,
                                    ),
                                  ),
                                  child: AnimatedBuilder(
                                    animation: page,
                                    builder: (context, child) => Opacity(
                                      opacity: page.value,
                                      child: FractionalTranslation(
                                        translation: Offset(
                                          (exiting ? -direction : direction) *
                                              .085 *
                                              (1 -
                                                  Curves.easeOutCubic.transform(
                                                    page.value,
                                                  )),
                                          direction == 0
                                              ? .025 * (1 - page.value)
                                              : 0,
                                        ),
                                        child: IgnorePointer(
                                          ignoring: changingStep || saving,
                                          child: child,
                                        ),
                                      ),
                                    ),
                                    child: _content(),
                                  ),
                                ),
                              ),
                        ),
                      ),
                      if (step != 7) _footer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navigation() => step == 7
      ? Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: MediaQuery.withNoTextScaling(child: const Brand(size: 28)),
        )
      : Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 24, 12),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: step > 0 && step != 7
                    ? IconButton.filledTonal(
                        onPressed: saving || changingStep ? null : previous,
                        tooltip: context.l10n.translate('Previous step'),
                        style: IconButton.styleFrom(
                          backgroundColor: context.kayleoSurfaces.soft,
                        ),
                        icon: const Icon(Icons.arrow_back_rounded, size: 21),
                      )
                    : null,
              ),
              const SizedBox(width: 18),
              if (step < 3)
                const Expanded(child: Center(child: Brand(size: 28)))
              else
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: (step - 2) / (_totalSteps - 3)),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(99),
                      color: context.kayleoPrimary,
                      backgroundColor: context.kayleoSurfaces.border,
                    ),
                  ),
                ),
              const SizedBox(width: 18),
              Semantics(
                label: context.l10n.translate(
                  'Step ${step + 1} of $_totalSteps',
                ),
                excludeSemantics: true,
                child: LocalizedText(
                  step < 3 ? '0${step + 1}' : '${step - 2} / 6',
                  style: TextStyle(
                    color: context.kayleoMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );

  Widget _footer() => Container(
    key: const Key('onboarding-footer'),
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
    decoration: BoxDecoration(
      color: context.kayleoBackground,
      border: Border(
        top: BorderSide(
          color: context.kayleoSurfaces.border.withValues(alpha: .65),
        ),
      ),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('onboarding-continue'),
            onPressed: saving || calculating || changingStep ? null : next,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 22),
                Expanded(
                  child: LocalizedText(
                    calculating
                        ? 'Personalizing with Kayleo…'
                        : saving
                        ? 'Saving your plan…'
                        : step == 8
                        ? 'Let’s start your day'
                        : step == 6
                        ? 'Create my plan'
                        : step == 0
                        ? 'Get started'
                        : 'Continue',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 4),
                saving || calculating
                    ? const Icon(Icons.more_horiz_rounded, size: 18)
                    : const Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
        ),
        if (step < 3)
          TextButton(
            key: const Key('explore-demo'),
            onPressed: saving || changingStep
                ? null
                : () => complete(demo: true),
            style: TextButton.styleFrom(foregroundColor: context.kayleoMuted),
            child: const LocalizedText(
              'Explore with sample data',
              style: TextStyle(fontSize: 12),
            ),
          )
        else ...[
          const SizedBox(height: 12),
          LocalizedText(
            'Your plan is always yours to adjust.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: context.kayleoMuted),
          ),
        ],
      ],
    ),
  );

  Widget _content() {
    if (step < 3) return _intro();
    if (step == 7) {
      return OnboardingPlanPreparation(
        profile: profile,
        onReady: () => goTo(8),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow(switch (step) {
          3 => 'YOUR DIRECTION',
          4 => 'THE STARTING POINT',
          5 => 'YOUR EVERYDAY',
          6 => 'YOUR FOOD PREFERENCES',
          _ => 'MADE FOR YOU',
        }),
        const SizedBox(height: 12),
        _heading(switch (step) {
          3 => 'What brings\nyou here?',
          4 => 'About you.',
          5 => 'Find your\nrhythm.',
          6 => 'What feels\ngood to eat?',
          _ => 'Your plan.\nYour pace.',
        }),
        const SizedBox(height: 12),
        LocalizedText(
          switch (step) {
            3 => 'Choose a direction. We’ll help you find a starting point.',
            4 => 'A few details help us estimate your daily energy needs.',
            5 => 'Think about a typical week, including work, walking and exercise.',
            6 => 'Pick the way you usually eat. There’s room for flexibility.',
            _ =>
              'A little structure for your day. Plenty of room for real life.',
          },
          style: TextStyle(
            fontSize: 14,
            height: 1.6,
            color: context.kayleoMuted,
          ),
        ),
        const SizedBox(height: 30),
        switch (step) {
          3 => _goals(),
          4 => _details(),
          5 => _activity(),
          6 => _diet(),
          _ => _plan(),
        },
      ],
    );
  }

  Widget _intro() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ExcludeSemantics(
        child: MediaQuery.withNoTextScaling(child: _IntroArtwork(index: step)),
      ),
      const SizedBox(height: 30),
      _heading(
        [
          'Snap it.\nKayleo gets it.',
          'Speak naturally.\nJust like you.',
          'Or type it.',
        ][step],
        centered: true,
      ),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: LocalizedText(
          [
            'Take a photo. Review the foods and portions.\nMake every detail your own.',
            'Say what you ate, in your own words.\nA simpler way to start your meal log.',
            'A quick note is all it takes to start.\nReview your meal before adding it.',
          ][step],
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.7,
            color: context.kayleoMuted,
          ),
        ),
      ),
      const SizedBox(height: 24),
      Semantics(
        label: context.l10n.translate('Introduction ${step + 1} of 3'),
        excludeSemantics: true,
        child: Row(
          key: const Key('onboarding-intro-progress'),
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            3,
            (index) => AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              width: step == index ? 24 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: step == index
                    ? context.kayleoPrimary
                    : context.kayleoSurfaces.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _eyebrow(String text) => LocalizedText(
    text,
    style: TextStyle(
      color: context.kayleoPrimary,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.7,
    ),
  );

  Widget _heading(String text, {bool centered = false}) => LocalizedText(
    text,
    textAlign: centered ? TextAlign.center : TextAlign.start,
    style: TextStyle(
      fontSize:
          MediaQuery.sizeOf(context).width < 360 ||
              MediaQuery.textScalerOf(context).scale(14) > 20
          ? 32
          : 38,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.6,
      height: 1.12,
    ),
  );

  Widget _goals() => Column(
    children: [
      for (final (goal, subtitle, icon) in [
        ('Feel healthier', 'Build a little more balance', Icons.spa_outlined),
        (
          'Lose weight',
          'Take a steady, thoughtful approach',
          Icons.south_east_rounded,
        ),
        (
          'Maintain weight',
          'Find your everyday balance',
          Icons.balance_rounded,
        ),
        (
          'Build muscle',
          'Support strength and recovery',
          Icons.fitness_center_rounded,
        ),
      ])
        _choice(
          goal,
          subtitle,
          icon,
          profile.goal == goal,
          () => setState(() => profile.goal = goal),
        ),
    ],
  );

  Widget _activity() => Column(
    children: [
      for (final (value, subtitle, icon) in [
        (
          'Mostly sitting',
          'Desk days, light movement',
          Icons.chair_alt_outlined,
        ),
        (
          'Lightly active',
          'Some walking, 1–3 workouts a week',
          Icons.directions_walk_rounded,
        ),
        (
          'Moderately active',
          'Regular movement, 3–5 workouts a week',
          Icons.directions_run_rounded,
        ),
        (
          'Very active',
          'An active job or frequent training',
          Icons.bolt_outlined,
        ),
      ])
        _choice(
          value,
          subtitle,
          icon,
          profile.activity == value,
          () => setState(() => profile.activity = value),
        ),
    ],
  );

  Widget _diet() => Column(
    children: [
      for (final (value, subtitle, icon) in [
        ('Everything', 'A little of everything', Icons.restaurant_rounded),
        ('Vegetarian', 'Plant foods, eggs and dairy', Icons.egg_outlined),
        ('Vegan', 'Entirely plant based', Icons.eco_outlined),
        (
          'Pescatarian',
          'Plant foods, fish and seafood',
          Icons.set_meal_outlined,
        ),
      ])
        _choice(
          value,
          subtitle,
          icon,
          profile.diet == value,
          () => setState(() => profile.diet = value),
        ),
      const SizedBox(height: 8),
      _note(
        Icons.tune_rounded,
        'A preference, not a rule. You can change this in Your space.',
      ),
    ],
  );

  Widget _details() => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          maxLength: 24,
          decoration: InputDecoration(
            labelText: context.l10n.translate('What should we call you?'),
            hintText: context.l10n.translate('Your first name'),
            counterText: '',
          ),
        ),
        const SizedBox(height: 22),
        _adaptiveFields(
          TextFormField(
            controller: age,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: context.l10n.translate('Age'),
              suffixText: 'years',
            ),
            validator: (value) {
              final number = int.tryParse(value?.trim() ?? '');
              return number == null || number < 18 || number > 100
                  ? 'Adults 18–100'
                  : null;
            },
          ),
          DropdownButtonFormField<String>(
            initialValue: profile.sex,
            isExpanded: true,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              color: context.kayleoText,
            ),
            decoration: InputDecoration(
              labelText: context.l10n.translate('Sex for calculation'),
            ),
            items: ['Prefer not to say', 'Female', 'Male']
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: LocalizedText(
                      value,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) => profile.sex = value!,
          ),
        ),
        const SizedBox(height: 22),
        _heightUnitSelector(),
        const SizedBox(height: 14),
        _adaptiveFields(
          _heightField(),
          _numberField(weight, 'Weight', 'kg', 30, 300),
        ),
        if (profile.goal == 'Lose weight') ...[
          const SizedBox(height: 24),
          _weightGoalFields(),
        ],
        const SizedBox(height: 24),
        _note(
          Icons.lock_outline_rounded,
          'Used to estimate your starting targets. Your details stay editable.',
        ),
        const SizedBox(height: 14),
        LocalizedText(
          'For adults 18+. If sex is unspecified, the calculation uses a midpoint. Estimates do not account for pregnancy or medical needs.',
          style: TextStyle(
            fontSize: 11,
            height: 1.6,
            color: context.kayleoMuted,
          ),
        ),
      ],
    ),
  );

  Widget _plan() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: forest,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.wb_sunny_outlined, color: lime, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: LocalizedText(
                    'YOUR DAILY STARTING POINT',
                    style: TextStyle(
                      color: lime,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            LocalizedText(
              number(profile.calorieTarget),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 54,
                fontWeight: FontWeight.w800,
                letterSpacing: -2,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 5),
            LocalizedText(
              'calories per day',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 7,
                child: Row(
                  children: [
                    Expanded(
                      flex: profile.proteinTarget * 4,
                      child: Container(color: KayleoColors.protein),
                    ),
                    Expanded(
                      flex: profile.carbTarget * 4,
                      child: Container(color: KayleoColors.carbs),
                    ),
                    Expanded(
                      flex: profile.fatTarget * 9,
                      child: Container(color: KayleoColors.fat),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final stack = MediaQuery.textScalerOf(context).scale(12) > 18;
          final width = stack
              ? constraints.maxWidth
              : (constraints.maxWidth - 20) / 3;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (label, value, color) in [
                ('Protein', profile.proteinTarget, KayleoColors.protein),
                ('Carbs', profile.carbTarget, KayleoColors.carbs),
                ('Fat', profile.fatTarget, KayleoColors.fat),
              ])
                Container(
                  width: width,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.kayleoSurfaces.card,
                    border: Border.all(color: context.kayleoSurfaces.border),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(height: 12),
                      LocalizedText(
                        '${value}g',
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.8,
                        ),
                      ),
                      LocalizedText(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.kayleoMuted,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          const Expanded(
            child: LocalizedText(
              'Built around you',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            onPressed: () => goTo(3),
            child: const LocalizedText(
              'Edit answers',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      _summaryRow(Icons.flag_outlined, 'Your direction', profile.goal),
      if (profile.goal == 'Lose weight' && profile.targetWeight != null)
        _summaryRow(
          Icons.trending_down_rounded,
          'Your goal',
          '${profile.targetWeight!.toStringAsFixed(profile.targetWeight! % 1 == 0 ? 0 : 1)} kg in ${profile.goalDurationMonths} months',
        ),
      if (profile.goal == 'Lose weight' && profile.targetWeight != null)
        _summaryRow(
          Icons.local_fire_department_outlined,
          'Starting deficit',
          'About ${profile.maintenance - profile.calorieTarget} cal/day',
        ),
      _summaryRow(
        Icons.directions_walk_rounded,
        'Your routine',
        profile.activity,
      ),
      _summaryRow(Icons.restaurant_rounded, 'Your food', profile.diet),
      const SizedBox(height: 14),
      _note(
        Icons.tune_rounded,
        aiPlanApplied
            ? 'Kayleo refined this estimate within its safety guardrails. Adjust your targets anytime in Your space.'
            : 'These are estimates, not strict rules. Adjust your targets anytime in Your space.',
      ),
      if (aiPlanApplied && aiPlanExplanation.isNotEmpty) ...[
        const SizedBox(height: 10),
        _note(Icons.auto_awesome_rounded, aiPlanExplanation),
      ],
      Center(
        child: TextButton.icon(
          onPressed: _showCalculation,
          icon: const Icon(Icons.info_outline_rounded, size: 16),
          label: const LocalizedText(
            'How we estimate your targets',
            style: TextStyle(fontSize: 11),
          ),
        ),
      ),
    ],
  );

  Widget _summaryRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: context.kayleoMuted),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              LocalizedText(
                label,
                style: TextStyle(fontSize: 12, color: context.kayleoMuted),
              ),
              LocalizedText(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  void _showCalculation() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocalizedText(
            'A starting point, explained.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          LocalizedText(
            'We estimate resting energy from your age, height, weight and sex, then account for your activity. Your estimated maintenance is ${number(profile.maintenance)} calories per day.',
          ),
          const SizedBox(height: 12),
          LocalizedText(
            profile.goal == 'Lose weight' && profile.targetWeight != null
                ? 'Your target of ${profile.targetWeight!.toStringAsFixed(profile.targetWeight! % 1 == 0 ? 0 : 1)} kg over ${profile.goalDurationMonths} months suggests a starting deficit of about ${profile.plannedDailyDeficit} calories per day. We cap ambitious deficits and apply a minimum calorie intake; the timeline is a guide, not a guarantee.'
                : 'Your selected goal adjusts the calorie target. Protein is based on body weight; the remaining energy is shared between fats and carbohydrates. When available, Kayleo refines this starting point within conservative limits around the formula estimate.',
          ),
          const SizedBox(height: 12),
          LocalizedText(
            'These general estimates do not account for pregnancy or medical needs. Your targets can be changed in Your space.',
            style: TextStyle(color: context.kayleoMuted, height: 1.6),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const LocalizedText('Got it'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _choice(
    String title,
    String subtitle,
    IconData icon,
    bool selected,
    VoidCallback action,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: action,
          borderRadius: BorderRadius.circular(21),
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: selected
                  ? context.kayleoPrimary
                  : context.kayleoSurfaces.card,
              borderRadius: BorderRadius.circular(21),
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
                        ? Theme.of(context).colorScheme.onPrimary
                              .withValues(alpha: .1)
                        : context.kayleoSurfaces.soft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 21,
                    color: selected
                        ? Theme.of(context).colorScheme.onPrimary
                        : context.kayleoPrimary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocalizedText(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: selected
                              ? Theme.of(context).colorScheme.onPrimary
                              : context.kayleoText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LocalizedText(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: selected
                              ? Theme.of(context).colorScheme.onPrimary
                                    .withValues(alpha: .75)
                              : context.kayleoMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 21,
                  color: selected
                      ? Theme.of(context).colorScheme.onPrimary
                      : context.kayleoSurfaces.border,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _note(IconData icon, String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.kayleoSurfaces.soft.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: context.kayleoPrimary),
        const SizedBox(width: 10),
        Expanded(
          child: LocalizedText(
            text,
            style: TextStyle(
              fontSize: 11,
              height: 1.6,
              color: context.kayleoMuted,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _adaptiveFields(Widget first, Widget second) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 320 ||
          MediaQuery.textScalerOf(context).scale(14) > 20) {
        return Column(children: [first, const SizedBox(height: 22), second]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 14),
          Expanded(child: second),
        ],
      );
    },
  );

  Widget _heightUnitSelector() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LocalizedText(
        'Height unit',
        style: TextStyle(
          color: context.kayleoMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          key: const Key('height-unit-selector'),
          segments: const [
            ButtonSegment(value: true, label: LocalizedText('Centimeters')),
            ButtonSegment(value: false, label: LocalizedText('Feet & inches')),
          ],
          selected: {heightInMetric},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => _changeHeightUnit(selection.first),
        ),
      ),
    ],
  );

  Widget _weightGoalFields() => Container(
    key: const Key('weight-goal-section'),
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: context.kayleoSurfaces.soft.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LocalizedText(
          'Set a weight goal',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        LocalizedText(
          'We’ll use this to create a gradual calorie-deficit starting point.',
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: context.kayleoMuted,
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('target-weight'),
          controller: targetWeight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: context.l10n.translate('Target weight'),
            suffixText: 'kg',
          ),
          validator: (value) {
            final target = double.tryParse(value?.trim() ?? '');
            final current = double.tryParse(weight.text.trim());
            if (target == null ||
                !target.isFinite ||
                target < 30 ||
                target > 300) {
              return 'Enter 30–300 kg';
            }
            if (current != null && target >= current) {
              return 'Must be below current weight';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        LocalizedText(
          'I’d like to work toward it in',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.kayleoMuted,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            key: const Key('goal-duration'),
            segments: const [
              ButtonSegment(value: 3, label: LocalizedText('3 mo')),
              ButtonSegment(value: 6, label: LocalizedText('6 mo')),
              ButtonSegment(value: 12, label: LocalizedText('12 mo')),
            ],
            selected: {profile.goalDurationMonths},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => profile.goalDurationMonths = selection.first),
          ),
        ),
        const SizedBox(height: 12),
        LocalizedText(
          'Your calorie target will respect a conservative deficit and minimum intake, even if the selected timeline is ambitious.',
          style: TextStyle(
            fontSize: 10,
            height: 1.5,
            color: context.kayleoMuted,
          ),
        ),
      ],
    ),
  );

  Widget _heightField() {
    if (heightInMetric) {
      return _numberField(height, 'Height', 'cm', 100, 250);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            key: const Key('height-feet'),
            controller: heightFeet,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: context.l10n.translate('Height'),
              suffixText: 'ft',
            ),
            validator: (_) => _imperialHeightError(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            key: const Key('height-inches'),
            controller: heightInches,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: context.l10n.translate('Inches'),
              suffixText: 'in',
            ),
            validator: (_) => _imperialHeightError(showRange: false),
          ),
        ),
      ],
    );
  }

  void _changeHeightUnit(bool metric) {
    if (metric == heightInMetric) return;
    if (metric) {
      final feet = int.tryParse(heightFeet.text.trim());
      final inches = int.tryParse(heightInches.text.trim());
      if (feet != null && inches != null && inches >= 0 && inches <= 11) {
        height.text = ((feet * 12 + inches) * 2.54).round().toString();
      }
    } else {
      final centimeters = double.tryParse(height.text.trim());
      if (centimeters != null && centimeters.isFinite) {
        final totalInches = (centimeters / 2.54).round();
        heightFeet.text = (totalInches ~/ 12).toString();
        heightInches.text = (totalInches % 12).toString();
      }
    }
    setState(() => heightInMetric = metric);
  }

  double _heightInCentimeters() {
    if (heightInMetric) return double.parse(height.text.trim());
    return (int.parse(heightFeet.text.trim()) * 12 +
            int.parse(heightInches.text.trim())) *
        2.54;
  }

  String? _imperialHeightError({bool showRange = true}) {
    final feet = int.tryParse(heightFeet.text.trim());
    final inches = int.tryParse(heightInches.text.trim());
    if (feet == null || inches == null || inches < 0 || inches > 11) {
      return showRange ? 'Enter a valid height' : null;
    }
    final centimeters = (feet * 12 + inches) * 2.54;
    if (centimeters < 100 || centimeters > 250) {
      return showRange ? '3 ft 4 in–8 ft 2 in' : null;
    }
    return null;
  }

  Widget _numberField(
    TextEditingController controller,
    String label,
    String unit,
    double min,
    double max,
  ) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(
      labelText: context.l10n.translate(label),
      suffixText: unit,
    ),
    validator: (value) {
      final number = double.tryParse(value?.trim() ?? '');
      return number == null || !number.isFinite || number < min || number > max
          ? '$min–$max'
          : null;
    },
  );
}

class _IntroArtwork extends StatelessWidget {
  const _IntroArtwork({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SizedBox(
      height: constraints.maxWidth < 320 ? 242 : 264,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: switch (index) {
          0 => _photo(context),
          1 => _voice(context),
          _ => _text(context),
        },
      ),
    ),
  );

  Widget _photo(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset('assets/images/salad.jpg', fit: BoxFit.cover),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0x700D241A)],
          ),
        ),
      ),
      Positioned(top: 18, left: 18, child: _pill('A FRESH PERSPECTIVE')),
      Positioned(
        bottom: 18,
        left: 18,
        right: 18,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.kayleoSurfaces.card,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 19,
                backgroundColor: lime,
                child: Icon(Icons.check_rounded, color: forest, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LocalizedText(
                      'Your meal, a little clearer.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: context.kayleoText,
                      ),
                    ),
                    const SizedBox(height: 3),
                    LocalizedText(
                      'You review every detail',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.kayleoMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _voice(BuildContext context) => Container(
    color: forest,
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pill('IN YOUR OWN WORDS'),
        const Spacer(),
        const LocalizedText(
          '“Rice, vegetables\nand lentils for lunch.”',
          style: TextStyle(
            fontSize: 23,
            height: 1.3,
            letterSpacing: -.8,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const Spacer(),
        Row(
          children: [
            const CircleAvatar(
              radius: 22,
              backgroundColor: lime,
              child: Icon(Icons.mic_none_rounded, color: forest),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  25,
                  (index) => Container(
                    width: 3,
                    height: [
                      9.0,
                      19.0,
                      30.0,
                      14.0,
                      36.0,
                      23.0,
                      11.0,
                    ][index % 7],
                    decoration: BoxDecoration(
                      color: lime.withValues(alpha: index < 18 ? .95 : .35),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _text(BuildContext context) => Container(
    color: context.kayleoSurfaces.soft,
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LocalizedText(
          'A NOTE TO YOUR DIARY',
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w800,
            color: context.kayleoPrimary,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: context.kayleoSurfaces.card,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: LocalizedText(
                  'A bowl of greens\nand grilled chicken',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.5,
                    color: context.kayleoText,
                  ),
                ),
              ),
              Container(width: 2, height: 30, color: context.kayleoPrimary),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/salad.jpg',
                width: 42,
                height: 42,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LocalizedText(
                'Ready for your review',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.kayleoPrimary,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: context.kayleoPrimary,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: lime,
      borderRadius: BorderRadius.circular(99),
    ),
    child: LocalizedText(
      text,
      style: const TextStyle(
        color: forest,
        fontSize: 8,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    ),
  );
}

class _OnboardingIdentity extends StatelessWidget {
  const _OnboardingIdentity();
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: forest,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(42),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Brand(size: 34, light: true),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const LocalizedText(
                          'Good food.\nReal life.\nYour rhythm.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 45,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -2,
                            height: 1.08,
                          ),
                        ),
                        const SizedBox(height: 24),
                        LocalizedText(
                          'A little clarity,\none meal at a time.',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color: Colors.white.withValues(alpha: .65),
                          ),
                        ),
                        const SizedBox(height: 32),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Image.asset(
                            'assets/images/bowl.jpg',
                            height: math.min(constraints.maxHeight * .27, 220),
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const LocalizedText(
                    'YOUR DAY, IN BALANCE.',
                    style: TextStyle(
                      color: lime,
                      fontSize: 9,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
