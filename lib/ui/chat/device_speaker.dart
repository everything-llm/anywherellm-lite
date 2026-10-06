import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'speaker.dart';

/// The [Speaker] the app uses on Android: the device's own text-to-speech engine.
class DeviceSpeaker implements Speaker {
  final _tts = FlutterTts();
  bool _ready = false;

  /// Counts the readings, so a stopped one goes no further.
  int _go = 0;

  @override
  Future<void> speak(String text) async {
    await stop();
    final go = _go;
    try {
      if (!_ready) {
        await _tts.awaitSpeakCompletion(true);
        _ready = true;
      }
      for (final part in speechParts(text)) {
        if (go != _go) return;
        if (await _tts.speak(part) != 1) {
          throw Exception(
            'The device has no speech engine that can read this.',
          );
        }
      }
    } on PlatformException catch (error) {
      throw Exception(error.message ?? 'The device could not read this aloud.');
    }
  }

  @override
  Future<void> stop() async {
    _go++;
    await _tts.stop();
  }
}

/// [text] cut into pieces short enough for Android's engine, which refuses more than about 4000
/// characters at once: at a line or sentence end where there is one.
List<String> speechParts(String text, {int most = 3500}) {
  final parts = <String>[];
  var rest = text.trim();
  while (rest.length > most) {
    final window = rest.substring(0, most);
    var cut = window.lastIndexOf('\n');
    if (cut < most ~/ 2) cut = window.lastIndexOf('. ') + 1;
    if (cut < most ~/ 2) cut = window.lastIndexOf(' ');
    if (cut <= 0) cut = most;
    parts.add(rest.substring(0, cut).trim());
    rest = rest.substring(cut).trim();
  }
  if (rest.isNotEmpty) parts.add(rest);
  return parts;
}
