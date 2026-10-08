import 'package:flutter_test/flutter_test.dart';
import 'package:anywherellm/core/copy.dart';

void main() {
  test('plural picks the word for the count', () {
    expect(plural(1, 'thread', 'threads'), '1 thread');
    expect(plural(0, 'thread', 'threads'), '0 threads');
  });

  test('grouped puts commas between thousands', () {
    expect(grouped(999), '999');
    expect(grouped(1040), '1,040');
    expect(grouped(12880), '12,880');
    expect(grouped(1234567), '1,234,567');
    expect(grouped(1000005), '1,000,005');
    expect(grouped(796), '796');
    expect(grouped(1284), '1,284');
  });
}
