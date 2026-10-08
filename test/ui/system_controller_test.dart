import 'dart:async';

import 'package:anywherellm/core/chat_log.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/rig.dart';

Future<Rig> started(FakeAnythingLlm llm) async {
  final rig = Rig(llm: llm, connection: sampleConnection);
  addTearDown(rig.dispose);
  await rig.start();
  return rig;
}

List<LoggedChat> logOf(int n) => [
  for (var i = n; i > 0; i--) LoggedChat(workspace: 'Q3', question: 'Q$i'),
];

void main() {
  test('exporting gives the file and a refusal says why', () async {
    final llm = planningServer()..exported = 'a,b';
    final rig = await started(llm);
    expect(
      String.fromCharCodes((await rig.system.exportChats(ChatExport.csv))!),
      'a,b',
    );
    expect(llm.calls, contains('exportChats:csv'));
    expect(rig.system.exporting, isFalse);
    llm.errors['exportChats'] = const ApiException('No');
    expect(await rig.system.exportChats(ChatExport.json), isNull);
    expect(rig.system.exportProblem?.title, 'Could not export the chats');
  });

  test('an export cut off by a new server leaves Export ready', () async {
    final llm = planningServer();
    final rig = await started(llm);
    final gate = llm.gates['exportChats'] = Completer<void>();
    llm.errors['exportChats'] = const ApiException('No');
    final exporting = rig.system.exportChats(ChatExport.csv);
    await pumpEventQueue();
    expect(rig.system.exporting, isTrue);
    await rig.settings.save('https://other:3001', 'K2');
    gate.complete();
    expect(await exporting, isNull);
    expect(rig.system.exporting, isFalse);
    expect(rig.system.exportProblem, isNull);
    await pumpEventQueue();
  });

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
      await rig.system.saveSettings('{"GenericOpenAiModelPref": "qwen3:14b"}'),
      isTrue,
    );
    final saved = rig.system.settingsRevision;
    gate.complete();
    await pumpEventQueue();
    expect(rig.system.settingsRevision, saved);
  });

  test('the chats are read a page at a time, newest first', () async {
    final llm = planningServer()..chatLog = logOf(45);
    final rig = await started(llm);
    await rig.system.readChats();
    expect(rig.system.chats!.length, 20);
    expect(rig.system.chats!.first.question, 'Q45');
    expect(rig.system.chatsMore, isTrue);
    await rig.system.moreChats();
    await rig.system.moreChats();
    expect(rig.system.chats!.length, 45);
    expect(rig.system.chats!.last.question, 'Q1');
    expect(rig.system.chatsMore, isFalse);
    expect(llm.calls.where((c) => c.startsWith('workspaceChats')), [
      'workspaceChats:0',
      'workspaceChats:1',
      'workspaceChats:2',
    ]);
  });

  test(
    'chats the server refuses say why, and a new server forgets them',
    () async {
      final llm = planningServer()..chatLog = logOf(3);
      final rig = await started(llm);
      await rig.system.readChats();
      expect(rig.system.chats, hasLength(3));
      llm.errors['workspaceChats'] = const ApiException('No');
      await rig.system.readChats();
      expect(rig.system.chatsProblem?.text, 'No');
      await rig.settings.save('https://other:3001', 'K2');
      expect(rig.system.chats, isNull);
      expect(rig.system.chatsProblem, isNull);
      // Lets the new server's loads end before the rig is torn down.
      await pumpEventQueue();
    },
  );
}
