import 'package:flutter/material.dart';

import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/phone_page.dart';
import 'connect_guide.dart';

/// A phone's camera view for a pairing code, over the whole window: a page under Back, heard as
/// Cancel, with the camera in a square as wide as the screen, where to find the code, what it
/// holds, and How connecting works, which [onHelp] opens.
class ScanView extends StatelessWidget {
  const ScanView({
    super.key,
    required this.camera,
    required this.onCancel,
    required this.onHelp,
  });

  /// The camera, reading codes.
  final Widget camera;
  final VoidCallback onCancel;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final note = Type.note(t.muted);
    return ColoredBox(
      color: t.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PhonePageHeader(
              title: 'Scan QR code',
              back: 'Cancel',
              onBack: onCancel,
            ),
            Expanded(
              child: ListView(
                padding: Sizes.pagePadding,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: ColoredBox(color: t.ink, child: camera),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 20,
                    children: [
                      Text(
                        'On your computer, open AnywhereLLM\'s Settings, Connection, '
                        'and choose Connect a phone.',
                        style: note,
                      ),
                      Text(
                        'The code holds the server\'s address and your key. Nothing is '
                        'sent anywhere but your server.',
                        style: note,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GuideLink('How connecting works', onTap: onHelp),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
