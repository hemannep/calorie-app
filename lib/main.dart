import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'core/app_state.dart';
import 'core/ui.dart';
import 'features/onboarding.dart';
import 'features/shell.dart';
import 'features/auth.dart';
import 'core/auth_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KayleoApp());
}

class KayleoApp extends StatefulWidget {
  const KayleoApp({
    super.key,
    this.state,
    this.splashDuration = const Duration(milliseconds: 1500),
  });
  final AppState? state;
  final Duration splashDuration;
  @override
  State<KayleoApp> createState() => _KayleoAppState();
}

class _KayleoAppState extends State<KayleoApp> {
  AppState? state;
  Object? error;
  bool ready = false;
  GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  String? identity;
  late final SemanticsHandle semantics;
  @override
  void initState() {
    super.initState();
    semantics = SemanticsBinding.instance.ensureSemantics();
    _start();
  }

  Future<void> _start() async {
    try {
      final results = await Future.wait([
        widget.state != null
            ? Future.value(widget.state!)
            : DemoAuthRepository().restore(),
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
        });
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
  void dispose() {
    if (widget.state == null) state?.dispose();
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
      ready = true;
    });
    if (widget.state == null && previous != null && previous != next) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  Widget _application() {
    final next = state?.signedOut == true
        ? 'signed-out'
        : state?.accountEmail ?? (ready ? 'signed-out' : 'loading');
    if (identity != next) {
      navigatorKey = GlobalKey<NavigatorState>();
      identity = next;
    }
    return MaterialApp(
      navigatorKey: navigatorKey,
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
          ? AuthScreen(onAuthenticated: authenticated)
          : state == null
          ? error == null
                ? const SplashScreen()
                : Scaffold(
                    body: EmptyState(
                      icon: Icons.storage_rounded,
                      title: 'Let’s try that again',
                      subtitle: 'Local storage was unavailable. Please restart the app.',
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
          ? AppShell(state: state!)
          : OnboardingScreen(state: state!),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Brand(size: c.maxWidth < 600 ? 72 : 100),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Your day, in balance.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
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
}
