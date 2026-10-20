import 'package:anywherellm/core/asks.dart';
import 'package:anywherellm/core/chat.dart';
import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_background.dart';
import '../support/fake_toolkit.dart';
import '../support/pump.dart';

const _id = '0123456789abcdef0123456789abcdef';

/// A toolkit whose skills ask here, holding request [_id] from workspace [workspace].
FakeToolkit _asking({String workspace = 'q3'}) {
  final now = clock.now().toUtc();
  return FakeToolkit()
    ..served = {ToolkitFeature.asks}
    ..asks[_id] = Ask(
      id: _id,
      host: 'muse-vm',
      origin: 'http://muse-vm:8463',
      skill: 'Library',
      workspace: workspace,
      why: 'Send a request to http://muse-vm:8463',
      expires: now.add(const Duration(minutes: 2)),
    );
}

/// Asks a question whose answer runs on, then has the skill say it waits on [_id].
Future<(FakeAnythingLlm, Harness)> _waiting(
  WidgetTester tester,
  FakeToolkit toolkit, {
  FakeBackground? background,
}) async {
  final llm = planningServer()..hold = true;
  final h = await pumpApp(
    tester,
    llm: llm,
    toolkitServer: toolkit,
    background: background,
  );
  await typeAndEnter(tester, 'Fetch the ntfy health page');
  llm.chat!.add(
    const StatusChunk(
      'Waiting for your approval in AnywhereLLM to reach muse-vm',
      ask: _id,
    ),
  );
  // The read, then the sheet sliding in.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
  return (llm, h);
}

Future<void> _end(WidgetTester tester, FakeAnythingLlm llm) async {
  llm.chat!.add(const ChatDone([]));
  await llm.chat!.close();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a skill\'s request asks here, and Allow once answers it', (
    tester,
  ) async {
    final toolkit = _asking();
    final (llm, _) = await _waiting(tester, toolkit);
    expect(find.text('Allow this?'), findsOneWidget);
    expect(find.text('http://muse-vm:8463'), findsOneWidget);
    expect(find.text('Send a request to http://muse-vm:8463'), findsOneWidget);
    expect(find.text('Q3 planning'), findsOneWidget);
    // The status line shows without its mark.
    expect(
      find.text('Waiting for your approval in AnywhereLLM to reach muse-vm'),
      findsOneWidget,
    );

    await tester.tap(control('Allow once'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(toolkit.calls, contains('decide:$_id=once'));
    expect(find.text('Allow this?'), findsNothing);
    await _end(tester, llm);
  });

  testWidgets('a request lies over a popup already open', (
    tester,
  ) async {
    final toolkit = _asking();
    final llm = planningServer()..hold = true;
    final h = await pumpApp(tester, llm: llm, toolkitServer: toolkit);
    await typeAndEnter(tester, 'Fetch the ntfy health page');
    h.shell.togglePopup(Popup.attach);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Add to your message'), findsOneWidget);
    llm.chat!.add(const StatusChunk('Waiting for your approval', ask: _id));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Allow this?'), findsOneWidget);
    // Hit-testable: Deny sits on top of the popup, not under it.
    expect(find.text('Deny').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Deny'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(toolkit.calls, contains('decide:$_id=deny'));
    expect(find.text('Allow this?'), findsNothing);
    await _end(tester, llm);
  });

  testWidgets('Back refuses it, as Deny does', (tester) async {
    final toolkit = _asking();
    final (llm, _) = await _waiting(tester, toolkit);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(toolkit.calls, contains('decide:$_id=deny'));
    expect(find.text('Allow this?'), findsNothing);
    await _end(tester, llm);
  });

  testWidgets('Always allow lists the address, which can be removed', (
    tester,
  ) async {
    final toolkit = _asking();
    final (llm, h) = await _waiting(tester, toolkit);
    expect(
      find.textContaining('Other ports on muse-vm still ask.'),
      findsOneWidget,
    );
    await tester.tap(control('Always allow'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(toolkit.calls, contains('decide:$_id=always'));
    await _end(tester, llm);

    h.shell.openSettings();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allowed addresses'));
    await tester.pumpAndSettle();
    expect(h.shell.settingsPage, SettingsPage.allowedAddresses);
    expect(find.text('http://muse-vm:8463'), findsOneWidget);
    await tester.tap(find.text('http://muse-vm:8463'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Stop allowing http://muse-vm:8463?'),
      findsOneWidget,
    );
    await tester.tap(control('Remove'));
    await tester.pumpAndSettle();
    expect(toolkit.calls, contains('forgetOrigin:http://muse-vm:8463'));
    expect(toolkit.calls.where((c) => c == 'allowedOrigins'), hasLength(1));
    expect(find.text('http://muse-vm:8463'), findsNothing);
    expect(find.textContaining('None yet.'), findsOneWidget);
  });

  testWidgets('one from another workspace shows nothing', (tester) async {
    final toolkit = _asking(workspace: 'household');
    final (llm, _) = await _waiting(tester, toolkit);
    expect(toolkit.calls, contains('ask:$_id'));
    expect(find.text('Allow this?'), findsNothing);
    await _end(tester, llm);
  });

  testWidgets('nothing is asked where the toolkit does not serve it', (
    tester,
  ) async {
    final toolkit = _asking()..served = {ToolkitFeature.memories};
    final (llm, _) = await _waiting(tester, toolkit);
    expect(toolkit.calls, isNot(contains('ask:$_id')));
    expect(find.text('Allow this?'), findsNothing);
    await _end(tester, llm);
  });

  testWidgets('the skill going on without it takes it away', (tester) async {
    final toolkit = _asking();
    final (llm, _) = await _waiting(tester, toolkit);
    expect(find.text('Allow this?'), findsOneWidget);
    llm.chat!.add(const StatusChunk('Running web-browsing'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Allow this?'), findsNothing);
    await _end(tester, llm);
  });

  testWidgets('time running out says so, over Close', (tester) async {
    final toolkit = _asking();
    final (llm, _) = await _waiting(tester, toolkit);
    await tester.pump(const Duration(minutes: 2));
    expect(find.text('The time ran out'), findsOneWidget);
    expect(control('Allow once'), findsNothing);
    await tester.tap(control('Close').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Allow this?'), findsNothing);
    expect(toolkit.calls, isNot(contains('decide:$_id=deny')));
    await _end(tester, llm);
  });

  testWidgets('a request that could not be read is read when named again', (
    tester,
  ) async {
    final toolkit = _asking()
      ..errors['ask'] = const ApiException('Try later.', status: 503);
    final (llm, _) = await _waiting(tester, toolkit);
    expect(find.text('Could not read the request'), findsOneWidget);
    await tester.tap(control('Close').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Allow this?'), findsNothing);

    toolkit.errors.remove('ask');
    llm.chat!.add(const StatusChunk('Running web-browsing'));
    await tester.pump(const Duration(milliseconds: 300));
    llm.chat!.add(const StatusChunk('Waiting for your approval', ask: _id));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Allow this?'), findsOneWidget);
    expect(toolkit.calls.where((c) => c == 'ask:$_id'), hasLength(2));
    await _end(tester, llm);
  });

  testWidgets('a request the key may not read says why', (tester) async {
    final toolkit = _asking()
      ..errors['ask'] = const ApiException(
        'Only AnywhereLLM\'s key can answer a request.',
        status: 403,
      );
    final (llm, _) = await _waiting(tester, toolkit);
    expect(find.text('Could not read the request'), findsOneWidget);
    expect(
      find.text('Only AnywhereLLM\'s key can answer a request.'),
      findsOneWidget,
    );
    await tester.tap(control('Close').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Allow this?'), findsNothing);
    await _end(tester, llm);
  });

  testWidgets(
    'out of sight it is a notification, taken back once the app shows',
    (tester) async {
      final background = FakeBackground();
      final toolkit = _asking();
      final llm = planningServer()..hold = true;
      final h = await pumpApp(
        tester,
        llm: llm,
        toolkitServer: toolkit,
        background: background,
      );
      await typeAndEnter(tester, 'Fetch the ntfy health page');
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
      llm.chat!.add(const StatusChunk('Waiting for your approval', ask: _id));
      await tester.pump(const Duration(milliseconds: 300));
      final thread = h.chat.activeThread;
      expect(background.asks, [
        'Approval needed in Q3 planning: Library asks to reach http://muse-vm:8463. @ q3/$thread',
      ]);

      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 300));
      expect(background.asks.last, isNull);
      expect(find.text('Allow this?'), findsOneWidget);
      await _end(tester, llm);
    },
  );
}
