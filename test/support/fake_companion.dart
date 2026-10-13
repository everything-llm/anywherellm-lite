import 'package:anywherellm/core/ports.dart';

/// A [CompanionApi] fake's presence: whether `/health` names it ([present]) and the features
/// it names then ([served]), remembered until asked [CompanionApi.features] `again`, counting
/// each real ask in [asked]. Every call is recorded in [calls] as `name` or `name:arg`, and an
/// error in [errors] under a method's name makes it fail.
mixin FakeCompanion implements CompanionApi {
  /// Whether `/health` names the companion.
  abstract bool present;

  /// The features `/health` names while [present].
  Set<String> get served;

  /// How many times [features] asked the server, rather than remembering.
  int asked = 0;
  Set<String>? _remembered;
  bool _known = false;

  final List<String> calls = [];
  final Map<String, Exception> errors = {};

  @override
  Future<Set<String>?> features({bool again = false}) async {
    calls.add('features${again ? ':again' : ''}');
    if (again || !_known) {
      asked++;
      _known = true;
      _remembered = present ? {...served} : null;
    }
    return _remembered;
  }

  /// Records [name] with [arg], fails it with its error in [errors], else answers [value].
  Future<T> run<T>(String name, T Function() value, [String? arg]) async {
    calls.add(arg == null ? name : '$name:$arg');
    if (errors[name] case final error?) throw error;
    return value();
  }
}
