// What the scripts that draw the app share: its own faces and a picture of the window. They sit
// outside `test/`, so the suite does not run them.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the app's own faces, which a test otherwise draws as boxes.
Future<void> loadFonts() async {
  const fonts = {
    'Instrument Sans': 'InstrumentSans.ttf',
    'JetBrains Mono': 'JetBrainsMono.ttf',
  };
  for (final MapEntry(key: family, value: file) in fonts.entries) {
    final loader = FontLoader(family)
      ..addFont(
        File('assets/fonts/$file')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)),
      );
    await loader.load();
  }
}

/// Writes what the window shows to [name] under [out], drawn at [density] pixels to a logical
/// one.
Future<void> capture(
  WidgetTester tester,
  Directory out,
  String name, {
  double density = 1,
}) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(
      Offset.zero & view.size,
      pixelRatio: density,
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('${out.path}/$name')..parent.createSync(recursive: true);
    file.writeAsBytesSync(png!.buffer.asUint8List());
  });
}
