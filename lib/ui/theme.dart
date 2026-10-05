import 'package:flutter/material.dart';

import 'tokens.dart';
import 'type.dart';

/// The Material theme for [brightness], carrying [Tokens] for everything Material has no name for.
ThemeData buildTheme(Brightness brightness) {
  final t = brightness == Brightness.dark ? Tokens.dark : Tokens.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: t.accent,
    onPrimary: t.onaccent,
    secondary: t.accent,
    onSecondary: t.onaccent,
    error: t.badfg,
    onError: t.badbg,
    surface: t.panel,
    onSurface: t.ink,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    dividerColor: t.line,
    // Hover states, no ripples.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: t.hover,
    focusColor: Colors.transparent,
    textTheme: TextTheme(bodyMedium: Type.sans(14.5, color: t.ink)),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.accent,
      selectionColor: t.accent.withValues(alpha: 0.28),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.panel2,
      surfaceTintColor: Colors.transparent,
    ),
    extensions: [t],
  );
}
