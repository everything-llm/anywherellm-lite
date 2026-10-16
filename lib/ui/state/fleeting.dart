import 'dart:async';

/// A value that holds for [lasts]: [show] sets it and starts the clock, [take] clears it early
/// and returns it, and when the clock runs out it is cleared and handed to [lapsed].
///
/// An owner calls [take] in its `dispose`, which stops the clock without calling [lapsed].
class Fleeting<T extends Object> {
  Fleeting(this.lasts, this.lapsed);

  final Duration lasts;
  final void Function(T value) lapsed;

  T? _value;
  Timer? _timer;

  T? get value => _value;

  void show(T value) {
    _timer?.cancel();
    _value = value;
    _timer = Timer(lasts, () {
      if (take() case final value?) lapsed(value);
    });
  }

  T? take() {
    _timer?.cancel();
    _timer = null;
    final value = _value;
    _value = null;
    return value;
  }
}
