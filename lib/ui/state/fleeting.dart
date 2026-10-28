import 'dart:async';

/// A value that holds for [lasts]: [show] sets it and starts the clock, [take] clears it early
/// and returns it, and when the clock runs out it is cleared and handed to [lapsed]. A
/// [Fleeting.held] one has no clock: it holds until [take] or the next [show], as a toast with
/// an action does until the person acts on it, closes it or leaves.
///
/// An owner calls [take] in its `dispose`, which stops the clock without calling [lapsed].
class Fleeting<T extends Object> {
  Fleeting(Duration this.lasts, this.lapsed);

  Fleeting.held() : lasts = null, lapsed = _never;

  static void _never(Object _) {}

  final Duration? lasts;
  final void Function(T value) lapsed;

  T? _value;
  Timer? _timer;

  T? get value => _value;

  void show(T value) {
    _timer?.cancel();
    _value = value;
    if (lasts case final lasts?) {
      _timer = Timer(lasts, () {
        if (take() case final value?) lapsed(value);
      });
    }
  }

  T? take() {
    _timer?.cancel();
    _timer = null;
    final value = _value;
    _value = null;
    return value;
  }
}
