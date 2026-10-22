import 'package:flutter/material.dart';

import '../core/prefs.dart';
import 'state/prefs_controller.dart';
import 'theme.dart';

/// The MaterialApp: light or dark as the person chose in Settings, the system's by default, and
/// text anywhere on screen can be selected.
class AnywhereLlmApp extends StatelessWidget {
  const AnywhereLlmApp({super.key, required this.home, this.prefs});

  final Widget home;

  /// The preferences that pick the theme. Without them the system's applies.
  final PrefsController? prefs;

  @override
  Widget build(BuildContext context) {
    final prefs = this.prefs;
    if (prefs == null) return _app(ThemeMode.system);
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => _app(switch (prefs.prefs.theme) {
        ThemePref.system => ThemeMode.system,
        ThemePref.light => ThemeMode.light,
        ThemePref.dark => ThemeMode.dark,
      }),
    );
  }

  /// The four themes, built once rather than on every change to the preferences.
  static final _light = buildTheme(Brightness.light);
  static final _dark = buildTheme(Brightness.dark);
  static final _lightMore = buildTheme(Brightness.light, more: true);
  static final _darkMore = buildTheme(Brightness.dark, more: true);

  Widget _app(ThemeMode mode) => MaterialApp(
    title: 'AnywhereLLM',
    debugShowCheckedModeBanner: false,
    theme: _light,
    darkTheme: _dark,
    highContrastTheme: _lightMore,
    highContrastDarkTheme: _darkMore,
    themeMode: mode,
    // Inside the Navigator, which supplies the Overlay that selection handles need.
    home: SelectionArea(child: home),
  );
}
