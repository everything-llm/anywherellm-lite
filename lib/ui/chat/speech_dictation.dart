import 'package:speech_to_text/speech_to_text.dart';

import 'dictation.dart';

/// The [Dictation] the app uses on Android: the device's own speech recognition. The text is
/// recognised by the service the device provides, which may send the audio to its maker.
class SpeechDictation implements Dictation {
  final _speech = SpeechToText();
  void Function()? _onDone;

  /// Calls the running go's [onDone], once.
  void _finish() {
    final done = _onDone;
    _onDone = null;
    done?.call();
  }

  @override
  Future<bool> start({
    required void Function(String words) onWords,
    required void Function() onDone,
  }) async {
    _onDone = onDone;
    final ready = await _speech.initialize(
      onStatus: (status) {
        // Done comes after the last words, which notListening does not wait for.
        if (status == SpeechToText.doneStatus) _finish();
      },
      onError: (_) => _finish(),
    );
    if (!ready) {
      _onDone = null;
      return false;
    }
    await _speech.listen(
      onResult: (result) => onWords(result.recognizedWords),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 4),
      ),
    );
    return true;
  }

  @override
  Future<void> stop() => _speech.stop();
}
