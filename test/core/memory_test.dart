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
    expect(MemorySwitches.fromJson({}).enabled, isFalse);
    expect(MemorySwitches.fromJson({}).learn, isTrue);
    MemorySwitches read(Map<String, Object?> settings) =>
        MemorySwitches.fromJson({'settings': settings});
    expect(read({'memory_enabled': 'true'}).enabled, isTrue);
    expect(read({'memory_enabled': 'false'}).enabled, isFalse);
    expect(read({'memory_enabled': null}).learn, isTrue);
    expect(read({'memory_auto_extraction': 'false'}).learn, isFalse);
    expect(read({'memory_auto_extraction': 'true'}).learn, isTrue);
  });
}
