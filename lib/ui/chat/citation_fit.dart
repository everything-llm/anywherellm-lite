import 'dart:math' as math;

/// The widths of the chips that lead a line of [count] chips in [width], in order: as many of
/// the candidates as fit, none narrower than its [readable] width, the rest of the [count]
/// folding into a chip [more] wide after them. Each chip shown takes its [readable] width, and
/// what is left is shared out towards each one's [natural] width. Chips are [gap] apart. With
/// room for none, the list is empty and only the folded chip shows.
List<double> fitChips({
  required List<double> readable,
  required List<double> natural,
  required int count,
  required double more,
  required double width,
  required double gap,
}) {
  assert(readable.length == natural.length && readable.length <= count);
  for (var shown = readable.length; shown > 0; shown--) {
    var used = gap * (shown - 1);
    for (var i = 0; i < shown; i++) {
      used += readable[i];
    }
    if (shown < count) used += gap + more;
    if (used > width) continue;
    return _shareOut(readable, natural, shown, width - used);
  }
  return const [];
}

/// The first [shown] chips' widths: each its readable width, and [spare] shared out among the
/// ones still short of their natural width, evenly, none past it.
List<double> _shareOut(
  List<double> readable,
  List<double> natural,
  int shown,
  double spare,
) {
  final widths = [for (var i = 0; i < shown; i++) readable[i]];
  var wanting = [
    for (var i = 0; i < shown; i++)
      if (natural[i] > widths[i]) i,
  ];
  while (spare > 0.5 && wanting.isNotEmpty) {
    final each = spare / wanting.length;
    for (final i in wanting) {
      final add = math.min(each, natural[i] - widths[i]);
      widths[i] += add;
      spare -= add;
    }
    wanting = [
      for (final i in wanting)
        if (natural[i] - widths[i] > 0.5) i,
    ];
  }
  return widths;
}
