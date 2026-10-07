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

  group('sign in', () {
    test('saves the key the server gives with the password', () async {
      llm.auth = ServerAuth.password;
      expect(await settings.signIn(' https://h:3001/ ', 'PASS-WORD'), isTrue);
      expect(
        store.saved,
        const Connection(
          baseUrl: 'https://h:3001',
          apiKey: 'MADE-KEY',
          password: 'PASS-WORD',
        ),
      );
      expect(llm.verified.single, store.saved);
      expect(settings.message, 'Signed in to h.');
      expect(settings.check, ConnectionCheck.idle);
    });

    test('reuses the AnywhereLLM key the server already has', () async {
      llm.apiKeys['AnywhereLLM'] = 'OLD-KEY';
      await settings.signIn('https://h:3001', '');
      expect(store.saved?.apiKey, 'OLD-KEY');
      expect(llm.apiKeys, {'AnywhereLLM': 'OLD-KEY'});
    });

    test('a wrong password saves nothing', () async {
      llm.auth = ServerAuth.password;
      expect(await settings.signIn('https://h:3001', 'WRONG'), isFalse);
      expect(store.saved, isNull);
      expect(settings.configured, isFalse);
      expect(settings.check, ConnectionCheck.failed);
      expect(settings.message, 'The server did not accept the password.');
    });

    test('a server with a password asks for it before signing in', () async {
      llm.auth = ServerAuth.password;
      expect(await settings.signIn('https://h:3001', ''), isFalse);
      expect(settings.message, 'Enter the server password.');
      expect(llm.calls, isNot(contains(startsWith('issueKey'))));
    });

    test('an open server keeps no password', () async {
      await settings.signIn('https://h:3001', 'typed anyway');
      expect(store.saved?.apiKey, 'MADE-KEY');
      expect(store.saved?.password, isNull);
    });

    test('a server with several users asks for a key', () async {
      llm.auth = ServerAuth.multiUser;
      expect(await settings.signIn('https://h:3001', 'PASS-WORD'), isFalse);
      expect(settings.needsKey, isTrue);
      expect(store.saved, isNull);
      expect(llm.calls, isNot(contains(startsWith('issueKey'))));
      expect(await settings.connect('https://h:3001', 'K1'), isTrue);
      await settings.clear();
      expect(settings.needsKey, isFalse);
    });

    test('a key the server gives but then refuses is not saved', () async {
      llm.verifyError = const ApiException('The server rejected the key.');
      expect(await settings.signIn('https://h:3001', ''), isFalse);
      expect(store.saved, isNull);
      expect(settings.message, 'The server rejected the key.');
    });

    test('a bad address says what is wrong and asks nothing', () async {
      expect(await settings.signIn('nonsense', ''), isFalse);
      expect(settings.check, ConnectionCheck.failed);
      expect(llm.calls, isEmpty);
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

  group('password', () {
    test('a server with a password says so once connected', () async {
      llm.auth = ServerAuth.password;
      await settings.connect('https://h:3001', 'K1');
      await pumpEventQueue();
      expect(settings.auth, ServerAuth.password);
    });

    test('an open server asks for none', () async {
      await settings.connect('https://h:3001', 'K1');
      await pumpEventQueue();
      expect(settings.auth, ServerAuth.none);
    });

    test('is saved only once the server takes it', () async {
      await settings.connect('https://h:3001', 'K1');
      expect(await settings.savePassword('WRONG'), isFalse);
      expect(
        settings.passwordMessage,
        'The server did not accept the password.',
      );
      expect(store.saved!.password, isNull);
      expect(await settings.savePassword('PASS-WORD'), isTrue);
      expect(settings.connection!.password, 'PASS-WORD');
      expect(store.saved!.password, 'PASS-WORD');
    });

    test('stays when the key is replaced on the same server', () async {
      store.saved = _saved.withPassword('PASS-WORD');
      await settings.load();
      await settings.connect('https://h:3001', 'K2');
      expect(settings.connection!.password, 'PASS-WORD');
      await settings.connect('https://other:3001', 'K2');
      expect(settings.connection!.password, isNull);
    });

    test('forgetting it keeps the key', () async {
      store.saved = _saved.withPassword('PASS-WORD');
      await settings.load();
      await settings.forgetPassword();
      expect(settings.connection, _saved);
      expect(store.saved, _saved);
    });
  });
}
