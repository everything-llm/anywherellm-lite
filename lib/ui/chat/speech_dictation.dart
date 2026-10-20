import 'package:speech_to_text/speech_to_text.dart';

import 'dictation.dart';

/// The [Dictation] the app uses on Android: the device's own speech recognition. The text is
/// recognised by the service the device provides, which may send the audio to its maker.
class SpeechDictation implements Dictation {
  final _speech = SpeechToText();
  void Function(DictationEnd how)? _onDone;

  /// Whether [stop] was asked for in the running go.
  bool _stopping = false;

  /// Counts the goes, so a result of an older one is not heard in the running go.
  int _go = 0;

  /// The recogniser's stop, while it is on its way. The next go waits for it, so the `done` it
  /// brings ends the go it stopped and never the next.
  Future<void>? _stopped;

  /// Calls the running go's [onDone], once.
  void _finish(DictationEnd how) {
    final done = _onDone;
    _onDone = null;
    done?.call(how);
  }

  @override
  Future<bool> start({
    required void Function(String words) onWords,
    required void Function(DictationEnd how) onDone,
  }) async {
    await _stopped;
    // A go the recogniser never reported done is over now that a new one starts.
    _finish(DictationEnd.stopped);
    final go = ++_go;
    _onDone = onDone;
    _stopping = false;
    var listening = false;
    try {
      final ready = await _speech.initialize(
        onStatus: (status) {
          // Done comes after the last words, which notListening does not wait for.
          if (status == SpeechToText.doneStatus) {
            _finish(_stopping ? DictationEnd.stopped : DictationEnd.paused);
          }
        },
        onError: (_) => _finish(DictationEnd.failed),
      );
      if (ready) {
        await _speech.listen(
          onResult: (result) {
            if (go == _go) onWords(result.recognizedWords);
          },
          listenOptions: SpeechListenOptions(
            partialResults: true,
            listenMode: ListenMode.dictation,
            pauseFor: const Duration(seconds: 4),
          ),
        );
        listening = true;
      }
    } on Exception {
      // A recognizer that is busy or missing throws instead of answering false.
    }
    if (!listening && go == _go) _onDone = null;
    return listening;
  }

  @override
  Future<void> stop() {
    _stopping = true;
    return _stopped = _speech.stop().whenComplete(() => _stopped = null);
  }
}
