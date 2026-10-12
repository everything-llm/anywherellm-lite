import 'package:flutter/material.dart';

import 'tokens.dart';
import 'type.dart';
import 'widgets/basics.dart';
import 'widgets/brand.dart';
import 'widgets/buttons.dart';
import 'widgets/centered_screen.dart';

/// Shown while the saved connection is read from the keyring.
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
            const Brand(),
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text(
                'Reading the saved connection...',
                style: Type.sans(14.5, color: t.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the app could not start.
class BootError extends StatelessWidget {
  const BootError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => CenteredScreen(
    children: [
      AlertBox(AlertKind.bad, 'The app could not start', text: message),
      const SizedBox(height: 16),
      AppButton('Try again', primary: true, onPressed: onRetry),
    ],
  );
}
