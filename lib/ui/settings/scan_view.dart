import 'package:flutter/material.dart';

import '../icons.dart';
import '../type.dart';

/// A phone's camera view for a pairing code, over the whole window: Cancel, the camera in a
/// square, where to find the code, and what it holds.
class ScanView extends StatelessWidget {
  const ScanView({super.key, required this.camera, required this.onCancel});

  /// The camera, reading codes.
  final Widget camera;
  final VoidCallback onCancel;

  static const _ground = Color(0xFF141420);

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: _ground,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Scan QR code',
                      style: Type.sans(
                        17,
                        weight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Cancel',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onCancel,
                    child: SizedBox.square(
                      dimension: 44,
                      child: Center(
                        child: AppIcon(
                          'close',
                          size: IconSize.small,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    children: [
                      SizedBox.square(
                        dimension: 250,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: camera,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Column(
                          children: [
                            Text(
                              'On your computer, open AnywhereLLM\'s Settings, Connection, '
                              'and choose Connect a phone.',
                              textAlign: TextAlign.center,
                              style: Type.sans(
                                15,
                                color: Colors.white.withValues(alpha: 0.92),
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'The code holds the server\'s address and your key. Nothing is '
                              'sent anywhere but your server.',
                              textAlign: TextAlign.center,
                              style: Type.sans(
                                12.5,
                                color: Colors.white.withValues(alpha: 0.7),
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
