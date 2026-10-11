import 'package:flutter/material.dart';

import 'brand.dart';

/// A whole screen with the brand above [children], in a column that scrolls when the window is
/// too short for it.
class CenteredScreen extends StatelessWidget {
  const CenteredScreen({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Brand(large: true),
                  ),
                  const SizedBox(height: 22),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
