// Grouping and wording, kept in one place so every page says the same things.

/// `1 item`, `3 items`.
String plural(int count, String one, String many) =>
    '$count ${count == 1 ? one : many}';

/// Groups [items] by [key], keeping the order in which each group first appears.
Map<String, List<T>> groupBy<T>(Iterable<T> items, String Function(T) key) {
  final groups = <String, List<T>>{};
  for (final item in items) {
    (groups[key(item)] ??= []).add(item);
  }
  return groups;
}
