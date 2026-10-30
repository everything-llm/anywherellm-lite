import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/users.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';
import '../support/pump.dart';
import '../support/rig.dart';

const sam = ServerUser(id: 1, name: 'Sam', role: 'admin');
const alex = ServerUser(id: 2, name: 'Alex', role: 'manager');
const robin = ServerUser(id: 3, name: 'Robin', role: 'default');

/// [planningServer] with several users: Sam the admin, Alex a manager, and Robin, whom
/// Household lists and Q3 planning does not.
FakeAnythingLlm severalUsers() {
  final llm = planningServer()
    ..several = true
    ..people = const [sam, alex, robin];
  llm.spaces = [
    for (final (i, w) in llm.spaces.indexed)
      FakeWorkspace(
        w.slug,
        w.name,
        id: i + 1,
        threads: w.threads,
        docs: w.docs,
      ),
  ];
  llm.members[2] = const [WorkspaceMember(id: 3)];
  return llm;
}

/// Prefs with chats on the sample server saved as [user].
FakePrefsStore savedAs(ServerUser user) =>
    FakePrefsStore(Prefs(users: {sampleConnection.baseUrl: user}));

Future<Rig> started(FakeAnythingLlm llm, {ServerUser? as}) async {
  final rig = Rig(
    llm: llm,
    connection: sampleConnection,
    prefsStore: as == null ? null : savedAs(as),
  );
  addTearDown(rig.dispose);
  await rig.start();
  return rig;
}

/// Whether the control a screen reader hears as [label] can be tapped.
bool enabled(WidgetTester tester, String label) =>
    tester.widget<Tappable>(control(label)).onTap != null;

void main() {
  group('the workspaces', () {
    test('show only those the chosen user opens', () async {
      final llm = severalUsers();
      final rig = await started(llm, as: robin);
      expect([for (final w in rig.chat.workspaces) w.slug], ['household']);
      expect(llm.calls, containsAll(['workspaceUsers:1', 'workspaceUsers:2']));
      expect(rig.chat.activeSlug, 'household');
    });

    test(
      'an admin or a manager sees every one, with no call for them',
      () async {
        for (final user in [sam, alex]) {
          final llm = severalUsers();
          final rig = await started(llm, as: user);
          expect(rig.chat.workspaces.length, 2);
          expect(
            llm.calls.where((c) => c.startsWith('workspaceUsers')),
            isEmpty,
          );
        }
      },
    );

    test('with no one chosen, every one shows', () async {
      final llm = severalUsers();
      final rig = await started(llm);
      expect(rig.chat.workspaces.length, 2);
      expect(llm.calls.where((c) => c.startsWith('workspaceUsers')), isEmpty);
    });

    test('one whose users cannot be read still shows', () async {
      final llm = severalUsers()
        ..errors['workspaceUsers'] = const ApiException(
          'The server rejected the key.',
          status: 401,
        );
      final rig = await started(llm, as: robin);
      expect(rig.chat.workspaces.length, 2);
      expect(rig.chat.problem, isNull);
    });
  });

  group('the chats', () {
    test('are made and asked as the chosen user', () async {
      final llm = severalUsers();
      final rig = await started(llm, as: robin);
      await rig.chat.send('What bills are due?');
      await pumpEventQueue();
      final thread = rig.chat.activeThread!;
      expect(llm.madeAs[thread], robin.id);
      expect(llm.lastUserId, robin.id);
    });

    test('name no user while no one is chosen', () async {
      final llm = planningServer();
      final rig = await started(llm);
      await rig.chat.select('household');
      await rig.chat.send('What bills are due?');
      await pumpEventQueue();
      expect(llm.madeAs.values.single, isNull);
      expect(llm.lastUserId, isNull);
    });
  });

  group('the Connection page', () {
    testWidgets('of a single-user server shows no one to save chats as', (
      tester,
    ) async {
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm);
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      expect(llm.calls, contains('multiUser'));
      expect(llm.calls, isNot(contains('users')));
      expect(find.text('Chats saved as'), findsNothing);
      expect(find.text('This server has several users'), findsNothing);
    });

    testWidgets('of a server with several users says whom chats are saved as, and that the key opens '
        'every chat', (tester) async {
      final h = await pumpApp(tester, llm: severalUsers());
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      expect(control('Chats saved as No one chosen yet. Change'), findsOne);
      expect(find.text('This server has several users'), findsOneWidget);
      expect(find.textContaining('can read every chat'), findsOneWidget);
      // Only connecting opens Who uses this app? by itself.
      expect(find.text('Who uses this app?'), findsNothing);
    });

    testWidgets(
      'opens Who uses this app? once after connecting, and Done waits for a pick',
      (tester) async {
        final llm = severalUsers();
        final h = await pumpApp(tester, llm: llm, connection: null);
        h.shell.openSettings(SettingsPage.connection);
        await tester.pumpAndSettle();
        await tester.enterText(
          find
              .bySemanticsLabel(RegExp(r'^(AnythingLLM s|S)erver address$'))
              .last,
          'https://h:3001',
        );
        await tester.enterText(
          find.bySemanticsLabel('AnythingLLM developer API key').last,
          'K1',
        );
        await tapVisible(tester, control('Connect'));
        await tester.pumpAndSettle();
        expect(find.text('Who uses this app?'), findsOneWidget);
        expect(find.textContaining('It is not a sign-in.'), findsOneWidget);
        expect(control('Sam, Admin'), findsOneWidget);
        expect(control('Alex, Manager'), findsOneWidget);
        expect(enabled(tester, 'Done'), isFalse);

        await tester.tap(control('Robin, Default'));
        await tester.pumpAndSettle();
        expect(enabled(tester, 'Done'), isTrue);
        await tester.tap(control('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Who uses this app?'), findsNothing);
        expect(h.prefs.chosenUser, robin);
        expect(h.prefsStore.saved.userOn('https://h:3001'), robin);
        expect(control('Chats saved as Robin. Change'), findsOneWidget);
        expect([for (final w in h.chat.workspaces) w.slug], ['household']);

        // It opened once: the page shown again does not open it.
        h.shell.openChat();
        await tester.pumpAndSettle();
        h.shell.openSettings(SettingsPage.connection);
        await tester.pumpAndSettle();
        expect(find.text('Who uses this app?'), findsNothing);
      },
    );

    testWidgets('closed without a pick, it keeps no one and stays closed', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: severalUsers(), connection: null);
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel(RegExp(r'^(AnythingLLM s|S)erver address$')).last,
        'https://h:3001',
      );
      await tester.enterText(
        find.bySemanticsLabel('AnythingLLM developer API key').last,
        'K1',
      );
      await tapVisible(tester, control('Connect'));
      await tester.pumpAndSettle();
      await tester.tap(control('Robin, Default'));
      await tester.pump();
      await tester.tap(control('Close').last);
      await tester.pumpAndSettle();
      expect(find.text('Who uses this app?'), findsNothing);
      expect(h.prefs.chosenUser, isNull);
      expect(control('Chats saved as No one chosen yet. Change'), findsOne);
      expect(h.chat.workspaces.length, 2);
    });

    testWidgets('a single-user server opens nothing after connecting', (
      tester,
    ) async {
      final h = await pumpApp(tester, llm: planningServer(), connection: null);
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel(RegExp(r'^(AnythingLLM s|S)erver address$')).last,
        'https://h:3001',
      );
      await tester.enterText(
        find.bySemanticsLabel('AnythingLLM developer API key').last,
        'K1',
      );
      await tapVisible(tester, control('Connect'));
      await tester.pumpAndSettle();
      expect(h.settings.configured, isTrue);
      expect(find.text('Who uses this app?'), findsNothing);
      expect(find.text('Chats saved as'), findsNothing);
    });

    testWidgets('Chats saved as changes whom, and the workspaces follow', (
      tester,
    ) async {
      final llm = severalUsers();
      final h = await pumpApp(tester, llm: llm, prefsStore: savedAs(robin));
      expect(h.chat.workspaces.length, 1);
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      await tapVisible(tester, control('Chats saved as Robin. Change'));
      await tester.pumpAndSettle();
      expect(find.text('Who uses this app?'), findsOneWidget);
      // The one chosen is picked already, so Done is on.
      expect(enabled(tester, 'Done'), isTrue);
      await tester.tap(control('Sam, Admin'));
      await tester.pump();
      await tester.tap(control('Done'));
      await tester.pumpAndSettle();
      expect(h.prefs.chosenUser, sam);
      expect(control('Chats saved as Sam. Change'), findsOneWidget);
      expect(h.chat.workspaces.length, 2);
    });

    testWidgets('says why the users could not be read', (tester) async {
      final llm = severalUsers()
        ..errors['users'] = const ApiException('database is locked');
      final h = await pumpApp(tester, llm: llm);
      h.shell.openSettings(SettingsPage.connection);
      await tester.pumpAndSettle();
      await tapVisible(
        tester,
        control('Chats saved as No one chosen yet. Change'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not read who uses this server'), findsOneWidget);
      expect(find.text('database is locked'), findsOneWidget);
      expect(enabled(tester, 'Done'), isFalse);
    });
  });
}
