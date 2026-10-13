/// A read or a write the server refused or could not do, or input that cannot be used. [status]
/// is null when the server gave no answer.
class ApiException implements Exception {
  const ApiException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// A call made before any server was set up in Settings.
class NotConfigured extends ApiException {
  const NotConfigured()
    : super(
        'No AnythingLLM server is set up yet. Add its address and key in Settings.',
      );
}

/// A streamed answer whose connection dropped after the server took the question: the server
/// may still finish it and save it to the chat.
class CutOff extends ApiException {
  const CutOff(super.message);
}
