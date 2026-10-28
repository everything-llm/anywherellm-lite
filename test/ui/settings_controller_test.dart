import 'dart:async';

import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/ui/state/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_settings.dart';

const _saved = Connection(baseUrl: 'https://h:3001', apiKey: 'K1');

void main() {
  late FakeAnythingLlm llm;
  late FakeSettingsStore store;
  late SettingsController settings;

  setUp(() {
    llm = FakeAnythingLlm();
    store = FakeSettingsStore();
    settings = SettingsController(llm, store, ConnectionHolder());
  });

  tearDown(() => settings.dispose());

  group('load', () {
    test('with nothing saved there is no connection', () async {
      await settings.load();
      expect(settings.configured, isFalse);
      expect(settings.keyringProblem, isNull);
    });

    test('uses the saved connection', () async {
      store.saved = _saved;
      await settings.load();
      expect(settings.connection, _saved);
    });

    test('a keyring that cannot be read is a notice, not a failure', () async {
      store.loadError = const ApiException('keyring locked');
      await settings.load();
      expect(settings.configured, isFalse);
      expect(settings.keyringProblem?.text, 'keyring locked');
    });
  });

  group('a test', () {
    test('connect verifies the normalised candidate first', () async {
      expect(await settings.connect(' https://h:3001/api/ ', ' K1 '), isTrue);
      expect(llm.verified, [_saved]);
      expect(settings.connection, _saved);
    });

    test('says why the server refused, and saves nothing', () async {
      llm.verifyError = const ApiException('The server rejected the key.');
      expect(await settings.connect('https://h:3001', 'bad'), isFalse);
      expect(settings.check, ConnectionCheck.failed);
      expect(settings.message, 'The server rejected the key.');
      expect(store.saved, isNull);
      expect(settings.configured, isFalse);
    });

    test('a bad address or an empty key never reaches the server', () async {
      await settings.connect('nonsense', 'K1');
      expect(settings.check, ConnectionCheck.failed);
      await settings.connect('https://h:3001', '  ');
      expect(settings.message, 'Enter the API key.');
      expect(llm.verified, isEmpty);
    });

    test('of the saved connection notifies on start and on finish', () async {
      store.saved = _saved;
      await settings.load();
      final states = <ConnectionCheck>[];
      settings.addListener(() => states.add(settings.check));
      await settings.testSaved();
      expect(states, [ConnectionCheck.testing, ConnectionCheck.ok]);
      expect(settings.message, 'Connected to h.');
    });
  });

  group('save', () {
    test('keeps the connection in use and in the store', () async {
      await settings.save('https://h:3001/', 'K1');
      expect(settings.connection, _saved);
      expect(store.saved, _saved);
      expect(settings.message, 'The key was saved.');
    });

    test('a keyring that refuses still leaves the connection in use', () async {
      store.saveError = const ApiException('keyring locked');
      await settings.save('https://h:3001', 'K1');
      expect(settings.connection, _saved);
      expect(store.saved, isNull);
      expect(settings.keyringProblem?.title, 'Could not save the connection');
    });

    test('an invalid address saves nothing', () async {
      await settings.save('nonsense', 'K1');
      expect(settings.configured, isFalse);
      expect(store.saved, isNull);
    });
  });

  group('connect', () {
    test('says whether it saved', () async {
      expect(await settings.connect('https://h:3001', 'K1'), isTrue);
      expect(store.saved, _saved);
      llm.verifyError = const ApiException('rejected');
      expect(await settings.connect('https://h:3001', 'K2'), isFalse);
      expect(store.saved, _saved);
    });
  });

  group('clear', () {
    test('forgets the connection and empties the store', () async {
      await settings.save('https://h:3001', 'K1');
      await settings.clear();
      expect(settings.configured, isFalse);
      expect(store.saved, isNull);
      expect(settings.message, 'The saved key was deleted.');
    });

    test('a keyring that refuses is a notice', () async {
      await settings.save('https://h:3001', 'K1');
      store.saveError = const ApiException('keyring locked');
      await settings.clear();
      expect(settings.configured, isFalse);
      expect(
        settings.keyringProblem?.title,
        'Could not remove the saved connection',
      );
    });
  });

  test(
    'a pairing code saves its connection once the key opens the server',
    () async {
      expect(await settings.pair(_saved), isTrue);
      expect(settings.connection, _saved);
      expect(store.saved, _saved);
    },
  );

  group('a test that comes back late', () {
    const other = Connection(baseUrl: 'https://other:3001', apiKey: 'K2');

    test('says nothing once the saved connection is forgotten', () async {
      store.saved = _saved;
      await settings.load();
      final gate = llm.gates['verify'] = Completer<void>();
      final testing = settings.testSaved();
      await pumpEventQueue();
      await settings.clear();
      gate.complete();
      await testing;
      expect(settings.check, ConnectionCheck.idle);
      expect(settings.message, 'The saved key was deleted.');
    });

    test('says nothing once another server is paired', () async {
      store.saved = _saved;
      await settings.load();
      final gate = llm.gates['verify'] = Completer<void>();
      final testing = settings.testSaved();
      await pumpEventQueue();
      llm.gates.remove('verify');
      await settings.pair(other);
      gate.complete();
      await testing;
      expect(settings.connection, other);
      expect(settings.check, ConnectionCheck.idle);
      expect(settings.message, isNot(contains('Connected to h')));
    });

    test('does not let an older test speak after a newer one', () async {
      store.saved = _saved;
      await settings.load();
      final slow = llm.gates['verify'] = Completer<void>();
      final first = settings.testSaved();
      await pumpEventQueue();
      llm.gates.remove('verify');
      await settings.testSaved();
      llm.verifyError = const ApiException('The server rejected the key.');
      slow.complete();
      await first;
      expect(settings.check, ConnectionCheck.ok);
      expect(settings.message, 'Connected to h.');
    });
  });
}
