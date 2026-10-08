/// A read or a write the server refused or could not do, or input that cannot be used. [status]
/// is null when the server gave no answer.
class ApiException implements Exception {
  const ApiException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// A relay's answer the app lost touch with while the relay goes on writing it, so it will
/// be in the chat when it is done.
class AnswerStillRunning extends ApiException {
  const AnswerStillRunning()
    : super(
        'Lost the connection to the relay. The answer is still being written there and will '
        'be in the chat when it is done.',
      );
}

/// A message the relay refused because its chat already has an answer running, which may have
/// been started on another device. The relay answers it with 409, in its own words.
class AlreadyAnswering extends ApiException {
  const AlreadyAnswering(super.message) : super(status: 409);
}

/// A call made before any server was set up in Settings.
class NotConfigured extends ApiException {
  const NotConfigured()
    : super(
        'No AnythingLLM server is set up yet. Add its address and key in Settings.',
      );
}
