import 'package:flutter_test/flutter_test.dart';
import 'package:everything/core/copy.dart';

void main() {
  test('plural picks the word for the count', () {
    expect(plural(1, 'thread', 'threads'), '1 thread');
    expect(plural(0, 'thread', 'threads'), '0 threads');
  });

  test('groupBy keeps first-seen order', () {
    final groups = groupBy(['b1', 'a1', 'b2'], (s) => s[0]);
    expect(groups.keys, ['b', 'a']);
    expect(groups['b'], ['b1', 'b2']);
  });
}
