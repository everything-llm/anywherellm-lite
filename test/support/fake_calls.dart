import 'dart:async';

/// How a fake records its calls and a test steers them: each call goes in [calls] as `name` or
/// `name:arg`, an error in [errors] under a method's name makes it fail, and a completer in
/// [gates] holds it until the test completes it.
mixin FakeCalls {
  final List<String> calls = [];
  final Map<String, Object> errors = {};
  final Map<String, Completer<void>> gates = {};

  /// Records [name] with [arg], waits for its gate, fails it with its error in [errors], else
  /// answers [value].
  Future<T> record<T>(String name, T Function() value, [String? arg]) async {
    calls.add(arg == null ? name : '$name:$arg');
    await gates[name]?.future;
    if (errors[name] case final error?) throw error;
    return value();
  }
}
