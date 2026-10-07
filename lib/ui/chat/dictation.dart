/// Turns speech into text for the composer. One go listens until it is stopped or the person
/// pauses.
abstract interface class Dictation {
  /// Starts listening. [onWords] gets everything heard in this go so far, each time in full.
  /// [onDone] is called once when listening ends, whether [stop] or a pause ended it. Resolves
  /// false when the device cannot listen, as when it has no speech recognition or the
  /// microphone is not allowed.
  Future<bool> start({
    required void Function(String words) onWords,
    required void Function() onDone,
  });

  /// Ends the go, which keeps what was heard.
  Future<void> stop();
}
