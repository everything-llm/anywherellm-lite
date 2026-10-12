import 'package:anywherellm/core/memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved memories are read under memories, skipping what is not one', () {
    final saved = SavedMemories.fromJson({
      'memories': {
        'global': [
          {'id': 1, 'content': 'Name is Anna.', 'scope': 'global'},
          {'content': 'no id'},
        ],
        'workspace': [
          {'id': 2, 'content': 'Boiler from 2019.', 'scope': 'workspace'},
        ],
      },
    });
    expect([for (final m in saved.global) m.text], ['Name is Anna.']);
    expect(saved.global.single.global, isTrue);
    expect(saved.workspace.single.global, isFalse);
    expect(SavedMemories.fromJson('nonsense').global, isEmpty);
  });

  test('the switches read as AnythingLLM reads them', () {
    MemorySwitches read(Map<String, Object?> settings) =>
        MemorySwitches.fromJson({'settings': settings});
    expect(read({}).enabled, isFalse);
    expect(read({}).learn, isTrue);
    expect(read({'memory_enabled': 'true'}).enabled, isTrue);
    expect(read({'memory_auto_extraction': 'false'}).learn, isFalse);
  });

  test('a long-term memory needs its facts', () {
    expect(LongMemory.fromJson({'count': 1}), isNull);
    expect(LongMemory.fromJson({'facts': []})!.count, 0);
  });

  test('the route is under the host\'s /_live', () {
    expect(
      memoryRoute(Uri.parse('https://h.ts.net:3001'), 'q 3', '/recall', {
        'q': 'tea',
      }).toString(),
      'https://h.ts.net:8445/_live/memory/q%203/recall?q=tea',
    );
  });

  test('when a fact was kept, in words', () {
    final now = DateTime(2026, 10, 12, 9);
    expect(keptText(DateTime(2026, 10, 12, 1), now), 'Today');
    expect(keptText(DateTime(2026, 10, 11, 23), now), 'Yesterday');
    expect(keptText(DateTime(2026, 9, 3), now), '3 Sep');
    expect(keptText(DateTime(2025, 9, 3), now), '3 Sep 2025');
  });
}
