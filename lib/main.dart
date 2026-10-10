import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'core/firebase_auth_repository.dart';
import 'core/auth_repository.dart';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'core/app_state.dart';
import 'services/notification_service.dart';
import 'services/cloud_sync_service.dart';
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
    final next = state?.signedOut == true
        ? 'signed-out'
        : state?.accountUid ??
              state?.accountEmail ??
              (ready ? 'signed-out' : 'loading');
    if (identity != next) {
      navigatorKey = GlobalKey<NavigatorState>();
      identity = next;
    }
    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [kayleoRouteObserver],
      title: 'Kayleo',
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
                        child: const Text('Retry'),
                      ),
                    ),
                  )
          : state!.onboarded
          ? AppShell(key: shellKey, state: state!)
          : OnboardingScreen(state: state!),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({
    super.key,
    this.duration = const Duration(milliseconds: 1500),
  });
  final Duration duration;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final typingDuration = reduceMotion
        ? Duration.zero
        : duration < const Duration(milliseconds: 1150)
        ? duration
        : const Duration(milliseconds: 1150);
    return Scaffold(
      backgroundColor: context.kayleoBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/kayleo-splash.png',
            fit: BoxFit.cover,
            color: dark ? const Color(0xFF243A2B) : null,
            colorBlendMode: BlendMode.multiply,
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, c) => Align(
                alignment: const Alignment(0, -.18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: TweenAnimationBuilder<int>(
                    key: const Key('splash-typewriter'),
                    tween: IntTween(begin: reduceMotion ? 7 : 0, end: 7),
                    duration: typingDuration,
                    builder: (context, count, _) {
                      final size = c.maxWidth < 600 ? 72.0 : 100.0;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
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
                                      if (count < 7)
                                        Container(
                                          width: 3,
                                          height: size * .66,
                                          margin: const EdgeInsets.only(
                                            left: 3,
                                            top: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: lime,
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),
                          AnimatedOpacity(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            opacity: count == 7 ? 1 : 0,
                            child: Text(
                              'Your day, in balance.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
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
