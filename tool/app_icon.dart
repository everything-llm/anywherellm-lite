// The pictures the launcher icon and the launch screen are made from, drawn with the app's own
// robin mark:
//
//   flutter test tool/app_icon.dart
//
// writes `assets/icon/icon.png`, `icon-foreground.png` and `splash.png`. Then run
// `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create`. It also writes
// the notification icon, the bird alone in white, straight to each density's
// `android/app/src/main/res/drawable-<density>/ic_notification.png`.
// It sits outside `test/`, so the suite does not run it.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:anywherellm/ui/widgets/robin_mark.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Each picture's side in pixels, and the mark's own box.
const _side = 1024.0;

/// The middle of the bird's outline on the mark's box, which each picture centres.
const _middle = Offset(498, 507);

/// The splash's tile: its side and its corner radius, as the design's icon tile rounds it.
const _tile = 640.0;
const _tileRadius = 0.225 * _tile;

/// The bird at [scale] of the mark's box, its middle on the picture's.
class _Bird extends StatelessWidget {
  const _Bird(this.scale);

  final double scale;

  @override
  Widget build(BuildContext context) => Transform(
    transform: Matrix4.identity()
      ..translateByDouble(_side / 2, _side / 2, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-_middle.dx, -_middle.dy, 0, 1),
    child: const RobinMark(size: _side, color: iconInk),
  );
}

/// The legacy launcher icon and the web icons: the bird on a square of the ground.
const _icon = ColoredBox(color: iconGround, child: _Bird(0.8));

/// The adaptive icon's foreground, inside the circle every launcher's mask keeps.
const _foreground = _Bird(0.66);

/// The launch screen: the bird on a rounded tile of the ground.
final _splash = Stack(
  children: [
    Center(
      child: Container(
        width: _tile,
        height: _tile,
        decoration: BoxDecoration(
          color: iconGround,
          borderRadius: BorderRadius.circular(_tileRadius),
        ),
      ),
    ),
    const _Bird(0.5),
  ],
);

/// The notification icon's side at each density: 24 dp.
const _notificationSides = {
  'mdpi': 24.0,
  'hdpi': 36.0,
  'xhdpi': 48.0,
  'xxhdpi': 72.0,
  'xxxhdpi': 96.0,
};

/// Writes [picture], drawn on a transparent square of [side], to [path].
Future<void> _draw(
  WidgetTester tester,
  Widget picture,
  String path, {
  double side = _side,
}) async {
  tester.view.physicalSize = Size.square(side);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: side,
          child: FittedBox(
            child: SizedBox.square(dimension: _side, child: picture),
          ),
        ),
      ),
    ),
  );
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File(path).writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('draws the icon pictures', (tester) async {
    tester.view
      ..physicalSize = const Size.square(_side)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _draw(tester, _icon, 'assets/icon/icon.png');
    await _draw(tester, _foreground, 'assets/icon/icon-foreground.png');
    await _draw(tester, _splash, 'assets/icon/splash.png');
    for (final MapEntry(key: density, value: side)
        in _notificationSides.entries) {
      await _draw(
        tester,
        const _Bird(0.9),
        'android/app/src/main/res/drawable-$density/ic_notification.png',
        side: side,
      );
    }
  });
}
