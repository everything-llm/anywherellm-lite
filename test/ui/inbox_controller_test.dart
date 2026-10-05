import 'package:flutter_test/flutter_test.dart';
import 'package:everything/core/models.dart';
import 'package:everything/core/ports.dart';
import 'package:everything/ui/state/inbox_controller.dart';

import '../support/fake_api.dart';
import '../support/rig.dart';

UploadFile file(String name, {int size = 10}) => UploadFile(
  name: name,
  length: () async => size,
  read: () async => List.filled(size, 65),
);

void main() {
  late Rig rig;
  late FakeApi api;
  late InboxController inbox;

  setUp(() {
    rig = Rig(FakeApi());
    api = rig.api;
    inbox = rig.inbox;
  });

  tearDown(() => rig.dispose());

  test('lists the staged files', () async {
    api.inboxValue = ['a.md', 'b.md'];
    await inbox.refresh();
    expect(inbox.staged, ['a.md', 'b.md']);
  });

  test('says so when it cannot be read', () async {
    api.errors['inbox'] = const ApiException('permission denied', status: 500);
    await inbox.refresh();
    expect(inbox.problems.single.title, 'Could not read the inbox');
    expect(inbox.problems.single.text, 'permission denied');
  });

  test(
    'asking again does not repeat the unreadable notice, and a read clears it',
    () async {
      api.errors['inbox'] = const ApiException(
        'permission denied',
        status: 500,
      );
      await inbox.refresh();
      await inbox.refresh();
      expect(inbox.problems, hasLength(1));
      api.errors.remove('inbox');
      await inbox.refresh();
      expect(inbox.problems, isEmpty);
    },
  );

  test('a refused file is listed after the unreadable notice', () async {
    api.errors['inbox'] = const ApiException('permission denied', status: 500);
    await inbox.refresh();
    inbox.report('Could not open the file picker', 'no display');
    expect(inbox.problems.map((p) => p.title), [
      'Could not read the inbox',
      'Could not open the file picker',
    ]);
  });

  test('stages a file and refreshes the list', () async {
    await inbox.upload([file('My Note.md')]);
    expect(api.calls, contains('upload:My Note.md'));
    expect(inbox.staged, ['my-note.md']);
    expect(inbox.problems, isEmpty);
  });

  test('a file over 2 MB is refused without being sent', () async {
    await inbox.upload([file('big.md', size: 2000001)]);
    expect(api.calls.where((c) => c.startsWith('upload')), isEmpty);
    expect(inbox.problems.single.title, 'Could not stage big.md');
    expect(inbox.problems.single.text, 'the file is over 2 MB');
  });

  test('the size limit is the one the server sent', () async {
    rig.overview.data = Overview(
      findings: const [],
      locations: const Locations(),
      limits: const Limits(upload: 1500000),
    );
    await inbox.upload([file('a.md', size: 1500001)]);
    expect(inbox.problems.single.text, 'the file is over 1.5 MB');
  });

  test('one bad file does not stop the others', () async {
    api.errors['upload'] = const ApiException('already staged', status: 409);
    await inbox.upload([file('a.md'), file('b.md')]);
    expect(inbox.problems.map((p) => p.title), [
      'Could not stage a.md',
      'Could not stage b.md',
    ]);
    api.errors.remove('upload');
    await inbox.upload([file('c.md')]);
    expect(
      inbox.problems,
      isEmpty,
      reason: 'a new batch starts with a clean slate',
    );
  });

  test(
    'a file that cannot be read is reported and the rest still go',
    () async {
      UploadFile unreadable(String name) => UploadFile(
        name: name,
        length: () async => throw const UnreadableFile('Is a directory'),
        read: () async => throw const UnreadableFile('Is a directory'),
      );
      await inbox.upload([unreadable('notes'), file('b.md')]);
      expect(api.calls, contains('upload:b.md'));
      expect(inbox.problems.single.title, 'Could not stage notes');
      expect(inbox.problems.single.text, 'Is a directory');
      expect(inbox.staged, ['b.md'], reason: 'the list is still refreshed');
    },
  );

  test('an empty batch does nothing', () async {
    await inbox.upload([]);
    expect(api.calls, isEmpty);
  });
}
