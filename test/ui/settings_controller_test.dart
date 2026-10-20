import 'package:anywherellm/core/toolkit.dart';
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

  group('test', () {
    test('verifies the normalised candidate and saves nothing', () async {
      await settings.test(' https://h:3001/api/ ', ' K1 ');
      expect(llm.verified, [_saved]);
      expect(settings.check, ConnectionCheck.ok);
      expect(settings.message, 'Connected to h.');
      expect(store.saved, isNull);
      expect(settings.configured, isFalse);
    });

    test('says why the server refused', () async {
      llm.verifyError = const ApiException('The server rejected the key.');
      await settings.test('https://h:3001', 'bad');
      expect(settings.check, ConnectionCheck.failed);
      expect(settings.message, 'The server rejected the key.');
    });

    test('a bad address or an empty key never reaches the server', () async {
      await settings.test('nonsense', 'K1');
      expect(settings.check, ConnectionCheck.failed);
      await settings.test('https://h:3001', '  ');
      expect(settings.message, 'Enter the API key.');
      expect(llm.verified, isEmpty);
    });

    test('notifies on start and on finish', () async {
      final states = <ConnectionCheck>[];
      settings.addListener(() => states.add(settings.check));
      await settings.test('https://h:3001', 'K1');
      expect(states, [ConnectionCheck.testing, ConnectionCheck.ok]);
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

  group('companions', () {
    final toolkit = Uri.parse('https://toolkit.example.com');

    test(
      'a pairing code saves where they run, once the key opens the server',
      () async {
        final saved = await settings.pair(
          Pairing(_saved, {toolkitCompanion.code: toolkit}),
        );
        expect(saved, isTrue);
        expect(settings.addressOf(toolkitCompanion), toolkit);
        expect(store.savedCompanions, {toolkitCompanion.code: toolkit});
      },
    );

    test('another key keeps them, and another server forgets them', () async {
      await settings.pair(Pairing(_saved, {toolkitCompanion.code: toolkit}));
      await settings.save(_saved.baseUrl, 'K2');
      expect(settings.addressOf(toolkitCompanion), toolkit);
      expect(store.savedCompanions, isNotEmpty);
      await settings.connect('https://other.example:3001', 'K1');
      expect(
        settings.addressOf(toolkitCompanion),
        isNull,
        reason: 'another server has none until a code names one',
      );
    });

    test('a code that names none keeps them on the same server', () async {
      await settings.pair(Pairing(_saved, {toolkitCompanion.code: toolkit}));
      await settings.pair(
        const Pairing(Connection(baseUrl: 'https://h:3001', apiKey: 'K2')),
      );
      expect(settings.addressOf(toolkitCompanion), toolkit);
      expect(store.savedCompanions, {toolkitCompanion.code: toolkit});
    });
  });
}
