/// How a go of listening ended: [Dictation.stop] ended it, the person paused, or recognition
/// failed.
enum DictationEnd { stopped, paused, failed }

/// Turns speech into text for the composer. One go listens until it is stopped or the person
/// pauses.
abstract interface class Dictation {
  /// Starts listening. [onWords] gets everything heard in this go so far, each time in full.
  /// [onDone] is called once when listening ends, with what ended it. Resolves
  /// false when the device cannot listen, as when it has no speech recognition or the
  /// microphone is not allowed.
  Future<bool> start({
    required void Function(String words) onWords,
    required void Function(DictationEnd how) onDone,
  });

  /// Ends the go, which keeps what was heard.
  Future<void> stop();
}
