import 'package:flutter/material.dart';

import 'theme.dart';

/// The MaterialApp: system light or dark, and text anywhere on screen can be selected.
class NilsApp extends StatelessWidget {
  const NilsApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nilson',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    themeMode: ThemeMode.system,
    // Inside the Navigator, which supplies the Overlay that selection handles need.
    home: SelectionArea(child: home),
  );
}
