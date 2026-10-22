import 'package:flutter/material.dart';
import 'package:path_drawing/path_drawing.dart';

import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/phone_page.dart';
import 'walkthrough.dart';

/// A phone's camera view for a pairing code, over the whole window: a page under Back, heard as
/// Cancel, with the camera in a square as wide as the screen under a frame that shows where the
/// code goes, where to find the code, what it
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
    final note = Type.note(t.ink);
    return ColoredBox(
      color: t.ground,
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
                      borderRadius: BorderRadius.circular(Sizes.card),
                      child: ColoredBox(
                        color: t.ink,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            camera,
                            IgnorePointer(
                              child: Center(
                                child: CustomPaint(
                                  size: const Size.square(180),
                                  painter: _Frame(
                                    t.ground.withValues(alpha: 0.55),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 20,
                    children: [
                      Text(
                        'The code comes from the toolkit\'s pair command, run on the '
                        'server\'s computer, or from another AnywhereLLM.',
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

/// Four rounded corners of a 180 px square, where the code is held, in [color].
class _Frame extends CustomPainter {
  _Frame(this.color);

  final Color color;

  static final _corners = parseSvgPathData(
    'M2 40V14A12 12 0 0 1 14 2h26 M140 2h26a12 12 0 0 1 12 12v26 '
    'M178 140v26a12 12 0 0 1-12 12h-26 M40 178H14A12 12 0 0 1 2 166v-26',
  );

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    _corners,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );

  @override
  bool shouldRepaint(_Frame old) => old.color != color;
}
