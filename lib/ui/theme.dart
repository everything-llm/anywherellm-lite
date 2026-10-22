import 'package:flutter/material.dart';

import 'tokens.dart';
import 'type.dart';

/// The Material theme for [brightness], in increased contrast when [more], carrying [Tokens] for
/// everything Material has no name for.
ThemeData buildTheme(Brightness brightness, {bool more = false}) {
  final t = Tokens.forTheme(brightness, more: more);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    secondary: t.accent,
    onSecondary: t.onAccent,
    error: t.danger,
    onError: t.tile,
    surface: t.tile,
    onSurface: t.ink,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.ground,
    canvasColor: t.ground,
    dividerColor: t.line,
    // Hover states, no ripples.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: t.sunken,
    focusColor: Colors.transparent,
    textTheme: TextTheme(bodyMedium: Type.body(t.ink)),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.accent,
      selectionColor: t.accent.withValues(alpha: 0.28),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.sunken,
      surfaceTintColor: Colors.transparent,
    ),
    extensions: [t],
  );
}
