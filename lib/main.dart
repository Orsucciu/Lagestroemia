// App entry. Boots logging, prefs, secure storage, opens the database and
// hands the Riverpod container over to [LagestroemiaApp].

import 'package:flutter/material.dart' show WidgetsFlutterBinding, MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/generated/app_localizations.dart';
import 'router/app_router.dart';
import 'state/providers.dart';
import 'state/settings_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initAppLogger();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: <Override>[
      settingsStateProvider.overrideWith(
        (ref) => SettingsNotifier(prefs),
      ),
    ],
    child: const LagestroemiaApp(),
  ));
}

class LagestroemiaApp extends ConsumerWidget {
  const LagestroemiaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsStateProvider);
    final router = ref.watch(routerProvider);
    final locale = settings.localeTag == null
        ? null
        : Locale(settings.localeTag!);
    return MaterialApp.router(
      title: 'Lagestroemia',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: settings.themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
