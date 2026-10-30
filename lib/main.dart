import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'core/firebase_auth_repository.dart';
import 'core/auth_repository.dart';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'core/app_state.dart';
import 'services/notification_service.dart';
import 'services/cloud_sync_service.dart';
import 'services/community_service.dart';
import 'services/home_widget_service.dart';
import 'core/ui.dart';
import 'features/onboarding.dart';
import 'features/shell.dart';
import 'features/milestones.dart';
import 'features/auth.dart';
import 'features/logging.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KayleoApp());
}

class KayleoApp extends StatefulWidget {
  const KayleoApp({
    super.key,
    this.state,
    this.repository,
    this.splashDuration = const Duration(milliseconds: 1500),
  });
  final AppState? state;
  final AuthRepository? repository;
  final Duration splashDuration;
  @override
  State<KayleoApp> createState() => _KayleoAppState();
}

class _KayleoAppState extends State<KayleoApp> with WidgetsBindingObserver {
  AppState? state;
  Object? error;
  bool ready = false;
  GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final shellKey = GlobalKey<AppShellState>();
  String? identity;
  late final SemanticsHandle semantics;
  StreamSubscription<dynamic>? authSubscription;
  bool _notificationPromptQueued = false;
  @override
  void initState() {
    super.initState();
    semantics = SemanticsBinding.instance.ensureSemantics();
    WidgetsBinding.instance.addObserver(this);
    unawaited(HomeWidgetService.instance.initialize());
    _start();
  }

  void _openWidgetAction(String action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = state;
      final context = navigatorKey.currentContext;
      if (!mounted ||
          current == null ||
          !current.onboarded ||
          current.signedOut ||
          context == null) {
        return;
      }
      switch (action) {
        case 'photo':
          unawaited(showLogger(context, current, openCamera: true));
        case 'voice':
          unawaited(showLogger(context, current, mode: 'Voice'));
        case 'barcode':
          unawaited(showLogger(context, current, mode: 'Barcode'));
        case 'streak':
          unawaited(openMilestones(context, current));
        case 'today':
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
          shellKey.currentState?.navigate(0);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _start() async {
    try {
      if (widget.state == null && widget.repository == null) {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
        authSubscription ??= FirebaseAuthRepository.instance.auth
            .authStateChanges()
            .listen((user) {
              if (user == null &&
                  state?.accountUid != null &&
                  state?.signedOut == false) {
                state!.markSignedOut();
              }
            });
      }
      final results = await Future.wait([
        widget.state != null
            ? Future.value(widget.state!)
            : (widget.repository ?? FirebaseAuthRepository.instance).restore(),
        Future<void>.delayed(widget.splashDuration),
      ]);
      if (!mounted) {
        if (widget.state == null) (results.first as AppState?)?.dispose();
        return;
      }
      if (mounted) {
        setState(() {
          state = results.first as AppState?;
          ready = true;
          if (widget.state == null) NotificationService.instance.attach(state);
          if (widget.state == null) CloudSyncService.instance.attach(state);
          if (widget.state == null) CommunityService.instance.attach(state);
          HomeWidgetService.instance.attach(state);
        });
        HomeWidgetService.instance.onAction = state != null && !state!.signedOut
            ? _openWidgetAction
            : null;
        HomeWidgetService.instance.dispatchPending();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value == AppLifecycleState.resumed) {
      HomeWidgetService.instance.refresh();
    }
    if (value == AppLifecycleState.resumed && widget.state == null) {
      NotificationService.instance.refresh();
      CloudSyncService.instance.refresh();
    }
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.state == null) {
      NotificationService.instance.attach(null);
      CloudSyncService.instance.attach(null);
      CommunityService.instance.attach(null);
    }
    if (widget.state == null) state?.dispose();
    HomeWidgetService.instance.attach(null);
    HomeWidgetService.instance.onAction = null;
    semantics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => state == null
      ? _application()
      : ListenableBuilder(
          listenable: state!,
          builder: (context, _) => _application(),
        );

  void authenticated(AppState next) {
    final previous = state;
    setState(() {
      state = next;
      if (widget.state == null) NotificationService.instance.attach(next);
      if (widget.state == null) CloudSyncService.instance.attach(next);
      if (widget.state == null) CommunityService.instance.attach(next);
      HomeWidgetService.instance.attach(next);
      ready = true;
    });
    HomeWidgetService.instance.onAction = _openWidgetAction;
    HomeWidgetService.instance.dispatchPending();
    if (widget.state == null && previous != null && previous != next) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  Widget _application() {
    if (widget.state == null &&
        NotificationService.instance.supported &&
        state?.onboarded == true &&
        !_notificationPromptQueued) {
      _notificationPromptQueued = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeAskForNotifications(),
      );
    }
    final next = state?.signedOut == true
        ? 'signed-out'
        : state?.accountUid ??
              state?.accountEmail ??
              (ready ? 'signed-out' : 'loading');
    if (identity != next) {
      navigatorKey = GlobalKey<NavigatorState>();
      identity = next;
    }
    AppLocalizations.setActiveLanguageCode(state?.languageCode);
    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [kayleoRouteObserver],
      title: 'Kayleo',
      locale: state?.languageCode == null || state!.languageCode == 'system'
          ? null
          : Locale(state!.languageCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supportedLocales) {
        if (locale == null) return const Locale('en');
        for (final supported in supportedLocales) {
          if (supported.languageCode == locale.languageCode) {
            return supported;
          }
        }
        return const Locale('en');
      },
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      theme: kayleoTheme(),
      darkTheme: kayleoTheme(brightness: Brightness.dark),
      themeMode: switch (state?.appearance) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      },
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: context.kayleoBackground,
                systemNavigationBarDividerColor: Colors.transparent,
              ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: ready && (state == null || state!.signedOut)
          ? AuthScreen(
              onAuthenticated: authenticated,
              repository: widget.repository,
            )
          : state == null
          ? error == null
                ? SplashScreen(duration: widget.splashDuration)
                : Scaffold(
                    body: EmptyState(
                      icon: Icons.storage_rounded,
                      title: 'Let’s try that again',
                      subtitle: 'Could not open your account. Check your connection and try again.',
                      action: FilledButton(
                        onPressed: () {
                          setState(() {
                            error = null;
                          });
                          _start();
                        },
                        child: const LocalizedText('Retry'),
                      ),
                    ),
                  )
          : state!.onboarded
          ? AppShell(key: shellKey, state: state!)
          : OnboardingScreen(state: state!),
    );
  }

  Future<void> _maybeAskForNotifications() async {
    final current = state;
    if (!mounted ||
        current == null ||
        !current.onboarded ||
        current.signedOut) {
      return;
    }
    if (current.storage.getBool('kayleo_notification_prompted_v1') == true) {
      return;
    }
    await current.storage.setBool('kayleo_notification_prompted_v1', true);
    if (!mounted) return;
    final enable = await showDialog<bool>(
      context: navigatorKey.currentContext!,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Center(child: KayleoIcon(size: 44, radius: 12)),
        title: const LocalizedText('Stay on track with reminders'),
        content: const LocalizedText(
          'Allow notifications for meal check-ins, hydration, weekly reviews, smart nudges, and milestone celebrations? You can change these anytime in Reminders.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const LocalizedText('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const LocalizedText('Allow notifications'),
          ),
        ],
      ),
    );
    if (enable == true && mounted) {
      await NotificationService.instance.enable(current);
    }
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.duration = const Duration(milliseconds: 1500),
  });
  final Duration duration;
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _soundChannel = MethodChannel('kayleo/home_widgets');
  static const List<String> _eyebrowPhrases = [
    'MINDFUL NUTRITION',
    'EAT WITH INTENTION',
    'FUELED BY NATURE',
    'DAILY VITALITY',
    'NOURISH TO FLOURISH',
    'BALANCED LIVING',
    'WHOLE FOOD ENERGY',
    'GENTLE PROGRESS',
    'CONSCIOUS FUELING',
    'BETTER EVERY BITE',
    'PURE NOURISHMENT',
    'YOUR WELLNESS RITUAL',
    'CALM CONSISTENCY',
    'CLEAN DAILY FUEL',
    'SMART MACRO HABITS',
    'HONOR YOUR BODY',
    'SIMPLY NOURISHED',
    'STEADY MOMENTUM',
    'FRESH PERSPECTIVE',
    'HEALTHY RHYTHMS',
    'THRIVE NATURALLY',
    'INTENTIONAL CHOICES',
    'FEEL YOUR BEST',
    'SUSTAINABLE BALANCE',
    'MINDFUL MACROS',
    'LISTEN TO YOUR BODY',
    'EFFORTLESS CLARITY',
    'REAL FOOD FIRST',
    'POWERED BY PLANTS',
    'STRENGTH IN BALANCE',
    'SMALL DAILY WINS',
    'VIBRANT ENERGY',
    'WHOLESOME HABITS',
    'RESTORE & REFUEL',
    'CRAFT YOUR ROUTINE',
    'NATURAL HARMONY',
    'JOYFUL NUTRITION',
    'CONSISTENT CARE',
    'FUEL YOUR GOALS',
    'NOURISH EVERY CELL',
    'SERENE WELLNESS',
    'LIGHT & ENERGIZED',
    'ROOTED IN HEALTH',
    'MINDFUL EATING',
    'ELEVATE YOUR DAY',
    'GOOD FOOD MOOD',
    'ACTIVE & NOURISHED',
    'WELLNESS IN MOTION',
    'GARDEN FRESH FOCUS',
    'CLEAR MIND & BODY',
    'BALANCED PLATE',
    'YOUR HEALTHY PACE',
    'QUIET DISCIPLINE',
    'FUEL FOR LIFE',
    'CULTIVATE VITALITY',
    'NOURISHING MOMENTS',
    'METABOLIC HARMONY',
    'RADIANT HEALTH',
    'PROGRESS OVER PERFECTION',
    'HYDRATE & NOURISH',
  ];

  late final String _eyebrow =
      _eyebrowPhrases[math.Random().nextInt(_eyebrowPhrases.length)];
  int _lastSoundCount = 0;

  void _triggerStepFeedback(int count, {required bool silent}) {
    if (silent || count <= _lastSoundCount) return;
    _lastSoundCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (count < 7) {
        unawaited(HapticFeedback.selectionClick());
        unawaited(
          _soundChannel
              .invokeMethod<void>('playSplashSound', 'tick')
              .catchError((_) {}),
        );
      } else if (count == 7) {
        unawaited(HapticFeedback.lightImpact());
        unawaited(
          _soundChannel
              .invokeMethod<void>('playSplashSound', 'chime')
              .catchError((_) {}),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final silent = reduceMotion || widget.duration == Duration.zero;
    final typingDuration = reduceMotion
        ? Duration.zero
        : widget.duration < const Duration(milliseconds: 1100)
        ? widget.duration
        : const Duration(milliseconds: 1100);
    return Scaffold(
      backgroundColor: context.kayleoBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: reduceMotion ? 1.0 : 1.045, end: 1.0),
            duration: reduceMotion ? Duration.zero : widget.duration,
            curve: Curves.easeOutCubic,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Image.asset(
              'assets/images/kayleo-splash.png',
              fit: BoxFit.cover,
              gaplessPlayback: true,
              color: dark ? const Color(0xFF243A2B) : null,
              colorBlendMode: BlendMode.multiply,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -.26),
                radius: .85,
                colors: [
                  (dark ? const Color(0xFF16231B) : const Color(0xFFFFFDF7))
                      .withValues(alpha: dark ? .52 : .64),
                  (dark ? const Color(0xFF101713) : const Color(0xFFF7F5ED))
                      .withValues(alpha: .0),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  (dark ? const Color(0xFF101713) : const Color(0xFFF7F5ED))
                      .withValues(alpha: .28),
                  Colors.transparent,
                  (dark ? const Color(0xFF101713) : const Color(0xFFF7F5ED))
                      .withValues(alpha: .12),
                ],
                stops: const [0, .55, 1],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, c) => Align(
                alignment: const Alignment(0, -.25),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: TweenAnimationBuilder<int>(
                    key: const Key('splash-typewriter'),
                    tween: IntTween(begin: reduceMotion ? 7 : 0, end: 7),
                    duration: typingDuration,
                    builder: (context, count, _) {
                      _triggerStepFeedback(count, silent: silent);
                      final size = c.maxWidth < 600 ? 68.0 : 92.0;
                      final done = count == 7;
                      final progress = (count / 7).clamp(0.0, 1.0);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedOpacity(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 260),
                            opacity: count > 0 ? 1 : 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    (dark
                                            ? const Color(0xFF1E2D24)
                                            : const Color(0xFFFFFFFF))
                                        .withValues(alpha: dark ? .78 : .82),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: dark
                                      ? Colors.white.withValues(alpha: .08)
                                      : forest.withValues(alpha: .08),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedScale(
                                    duration: reduceMotion
                                        ? Duration.zero
                                        : const Duration(milliseconds: 320),
                                    scale: done ? 1.15 : .85,
                                    curve: Curves.easeOutBack,
                                    child: Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: lime,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  LocalizedText(
                                    _eyebrow,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.4,
                                      color: dark ? lime : forest,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          AnimatedScale(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 360),
                            curve: Curves.easeOutBack,
                            scale: done ? 1.0 : .97,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Opacity(opacity: 0, child: Brand(size: size)),
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Brand(
                                          size: size,
                                          visibleCharacters: count,
                                        ),
                                        if (!done)
                                          Container(
                                            width: 2.5,
                                            height: size * .58,
                                            margin: const EdgeInsets.only(
                                              left: 3,
                                              top: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: lime,
                                              borderRadius:
                                                  BorderRadius.circular(99),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          AnimatedSlide(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            offset: done ? Offset.zero : const Offset(0, 0.22),
                            child: AnimatedOpacity(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 280),
                              curve: Curves.easeOut,
                              opacity: done ? 1 : 0,
                              child: LocalizedText(
                                'Your day, in balance.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: c.maxWidth < 360 ? 15 : 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: .25,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          AnimatedOpacity(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 240),
                            opacity: count > 0 ? 1 : 0,
                            child: Semantics(
                              label: context.l10n.translate('Loading'),
                              child: ExcludeSemantics(
                                child: SizedBox(
                                  width: 48,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(begin: 0, end: progress),
                                      duration: reduceMotion
                                          ? Duration.zero
                                          : const Duration(milliseconds: 220),
                                      curve: Curves.easeOut,
                                      builder: (context, value, _) =>
                                          LinearProgressIndicator(
                                            value: value,
                                            minHeight: 2.5,
                                            backgroundColor: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: .08),
                                            color: lime,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
