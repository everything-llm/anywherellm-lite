import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/rig.dart';

Future<Rig> started(FakeAnythingLlm llm) async {
  final rig = Rig(llm: llm, connection: sampleConnection);
  addTearDown(rig.dispose);
  await rig.start();
  return rig;
}

void main() {
  test(
    'a read cut off by a new server does not hold up the new one\'s',
    () async {
      final llm = planningServer();
      final rig = await started(llm);
      final gate = llm.gates['systemSettings'] = Completer<void>();
      unawaited(rig.system.readSettings());
      await pumpEventQueue();
      await rig.settings.save('https://other:3001', 'K2');
      llm.gates.remove('systemSettings');
      await rig.system.wantSettings();
      expect(rig.system.settings, isNotNull);
      expect(llm.calls.where((c) => c == 'systemSettings'), hasLength(2));
      gate.complete();
      await pumpEventQueue();
    },
  );

  test('a read that lands after a save is not kept over it', () async {
    final llm = planningServer();
    final rig = await started(llm);
    await rig.system.wantSettings();
    final gate = llm.gates['systemSettings'] = Completer<void>();
    unawaited(rig.system.readSettings());
    await pumpEventQueue();
    llm.gates.remove('systemSettings');
    expect(
      await rig.system.saveSettings({'GenericOpenAiModelPref': 'qwen3:14b'}),
      isTrue,
    );
    expect(rig.system.settings?['GenericOpenAiModelPref'], 'qwen3:14b');
    // The read under way answers with what the server held before the save.
    llm.system = {...llm.system, 'GenericOpenAiModelPref': 'llama3.1:8b'};
    gate.complete();
    await pumpEventQueue();
    expect(rig.system.settings?['GenericOpenAiModelPref'], 'qwen3:14b');
    expect(llm.calls.where((c) => c == 'systemSettings'), hasLength(2));
  });
}
