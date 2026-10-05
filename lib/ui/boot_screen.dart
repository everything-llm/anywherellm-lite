import 'package:flutter/material.dart';

import 'tokens.dart';
import 'type.dart';
import 'widgets/basics.dart';
import 'widgets/brand.dart';
import 'widgets/buttons.dart';
import 'widgets/centered_screen.dart';

/// Shown while the first read of the libraries is under way.
class BootScreen extends StatelessWidget {
  const BootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Brand(size: 34),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                'Reading the libraries...',
                style: Type.sans(14.5, color: t.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the libraries could not be read.
class BootError extends StatelessWidget {
  const BootError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => CenteredScreen(
    children: [
      AlertBox(AlertKind.bad, 'The libraries could not be read', text: message),
      const SizedBox(height: 16),
      NilsButton('Try again', primary: true, onPressed: onRetry),
    ],
  );
}
