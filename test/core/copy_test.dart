import 'package:flutter_test/flutter_test.dart';
import 'package:anywherellm/core/copy.dart';

void main() {
  test('plural picks the word for the count', () {
    expect(plural(1, 'thread', 'threads'), '1 thread');
    expect(plural(0, 'thread', 'threads'), '0 threads');
  });
}
