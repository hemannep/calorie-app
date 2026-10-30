import 'package:calorie_app/core/app_state.dart';
import 'package:calorie_app/core/localization.dart';
import 'package:calorie_app/features/settings.dart';
import 'package:calorie_app/features/shell.dart';
import 'package:calorie_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLocalizations.setActiveLanguageCode(null);
  });

  test('language choice persists with the account state', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SharedPreferences.getInstance();
    final state = AppState(storage);

    for (final code in ['ne', 'hi', 'es', 'zh', 'ja', 'ko', 'en']) {
      await state.setLanguage(code);
      await state.writesComplete;

      final restored = await AppState.load();
      expect(restored.languageCode, code);
    }
  });

  test('unsupported language choices are ignored', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SharedPreferences.getInstance();
    final state = AppState(storage);

    await state.setLanguage('xx');

    expect(state.languageCode, 'system');
  });

  test('translations fall back to English and then to the key', () {
    const spanish = AppLocalizations(Locale('es'));

    expect(spanish.t('today'), 'Hoy');
    expect(spanish.t('unknownKey'), 'unknownKey');
  });

  test(
    'legacy screen copy and interpolated values use the active language',
    () {
      const spanish = AppLocalizations(Locale('es'));
      const nepali = AppLocalizations(Locale('ne'));
      const chinese = AppLocalizations(Locale('zh'));
      const japanese = AppLocalizations(Locale('ja'));
      const korean = AppLocalizations(Locale('ko'));

      expect(spanish.translate('Add food'), 'Añadir Comida');
      expect(spanish.translate('120 calories today'), '120 Calorías Hoy');
      expect(nepali.translate('Save meal'), 'सुरक्षित खाना');
      expect(chinese.translate('Your daily plan'), '您的每日计划');
      expect(japanese.translate('Your daily plan'), '1日のプラン');
      expect(korean.translate('Your daily plan'), '나의 일일 플랜');
    },
  );

  test('flags are provided for non-English languages and not for English', () {
    expect(AppLocalizations.flagFor('en'), isNull);
    expect(AppLocalizations.flagFor('system'), isNull);
    expect(AppLocalizations.flagFor('ne'), '🇳🇵');
    expect(AppLocalizations.flagFor('hi'), '🇮🇳');
    expect(AppLocalizations.flagFor('es'), '🇪🇸');
    expect(AppLocalizations.flagFor('zh'), '🇨🇳');
    expect(AppLocalizations.flagFor('ja'), '🇯🇵');
    expect(AppLocalizations.flagFor('ko'), '🇰🇷');
    expect(AppLocalizations.displayNameFor('en'), 'English');
    expect(AppLocalizations.displayNameFor('zh'), '🇨🇳 中文');
    expect(AppLocalizations.displayNameFor('ja'), '🇯🇵 日本語');
    expect(AppLocalizations.displayNameFor('ko'), '🇰🇷 한국어');
  });

  testWidgets(
    'LanguageSheet shows native names and flags for non-English options without a flag on English',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final storage = await SharedPreferences.getInstance();
      final state = AppState(storage)..onboarded = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LanguageSheet(state: state)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('language-flag-en')), findsNothing);
      expect(find.byKey(const Key('language-flag-ne')), findsOneWidget);
      expect(find.byKey(const Key('language-flag-hi')), findsOneWidget);
      expect(find.byKey(const Key('language-flag-es')), findsOneWidget);
      expect(find.byKey(const Key('language-flag-zh')), findsOneWidget);
      expect(find.byKey(const Key('language-flag-ja')), findsOneWidget);
      expect(find.byKey(const Key('language-flag-ko')), findsOneWidget);

      expect(find.text('English'), findsOneWidget);
      expect(find.text('नेपाली'), findsOneWidget);
      expect(find.text('हिन्दी'), findsOneWidget);
      expect(find.text('Español'), findsOneWidget);
      expect(find.text('中文'), findsOneWidget);
      expect(find.text('日本語'), findsOneWidget);
      expect(find.text('한국어'), findsOneWidget);
    },
  );

  testWidgets('changing language updates the entire application immediately', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await SharedPreferences.getInstance();
    final state = AppState(storage)..onboarded = true;

    await tester.pumpWidget(
      KayleoApp(state: state, splashDuration: Duration.zero),
    );
    await tester.pumpAndSettle();

    await state.setLanguage('ja');
    await tester.pumpAndSettle();
    expect(find.text('今日'), findsWidgets);

    await state.setLanguage('zh');
    await tester.pumpAndSettle();
    expect(find.text('今天'), findsWidgets);

    await state.setLanguage('ko');
    await tester.pumpAndSettle();
    expect(find.text('오늘'), findsWidgets);

    final shell = tester.state<AppShellState>(find.byType(AppShell));
    shell.navigate(5);
    await tester.pumpAndSettle();
    expect(find.text('🇰🇷 한국어'), findsOneWidget);
  });
}
