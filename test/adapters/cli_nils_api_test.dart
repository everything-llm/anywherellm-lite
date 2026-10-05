import 'dart:convert';
import 'dart:io';

import 'package:everything/adapters/cli_nils_api.dart';
import 'package:everything/adapters/nils_command.dart';
import 'package:everything/core/ports.dart';
import 'package:flutter_test/flutter_test.dart';

/// One call [CliNilsApi] made to a process.
class _Call {
  _Call(this.executable, this.arguments, this.workingDirectory);

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
}

/// A [RunProcess] that records each call and answers with [answer], or throws [failure].
class _Runner {
  ProcessResult Function(List<String> arguments) answer = (_) =>
      ProcessResult(1, 0, '[]', '');
  Object? failure;
  final calls = <_Call>[];

  Future<ProcessResult> call(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    calls.add(_Call(executable, arguments, workingDirectory));
    final error = failure;
    if (error != null) throw error;
    return answer(arguments);
  }
}

ProcessResult _ok(Object json) => ProcessResult(1, 0, jsonEncode(json), '');

ProcessResult _failed(String stderr, [int code = 1]) =>
    ProcessResult(1, code, '', stderr);

void main() {
  late _Runner runner;
  late CliNilsApi api;

  setUp(() {
    runner = _Runner();
    api = CliNilsApi(
      NilsCommand('uv', const ['run', 'nils'], Directory('/repo')),
      run: runner.call,
    );
  });

  group('reads', () {
    test('overview runs `nils view overview` in the checkout', () async {
      runner.answer = (_) => _ok({
        'research': {'documents': 4},
        'skills': {'count': 1},
        'findings': [],
        'locations': {'research_root': '/r'},
        'limits': {'upload': 40},
      });
      final overview = await api.overview();
      expect(overview.research.count, 4);
      expect(overview.locations.researchRoot, '/r');
      final call = runner.calls.single;
      expect(call.executable, 'uv');
      expect(call.arguments, ['run', 'nils', 'view', 'overview']);
      expect(call.workingDirectory, '/repo');
    });

    test('research and skills decode their lists', () async {
      runner.answer = (arguments) => _ok(
        arguments.last == 'research'
            ? [
                {'path': 'a/b.md', 'summary': 'S'},
              ]
            : [
                {'name': 'scaffold', 'description': 'D'},
              ],
      );
      expect((await api.research()).single.path, 'a/b.md');
      expect((await api.skills()).single.name, 'scaffold');
    });

    test('a document and a skill are asked for by path and by name', () async {
      runner.answer = (arguments) => _ok(
        arguments.contains('research-doc')
            ? {'path': 'a/b.md', 'text': 'T', 'meta': null}
            : {'name': 'scaffold', 'text': 'T', 'meta': null},
      );
      expect((await api.researchDoc('a/b.md')).text, 'T');
      expect(runner.calls.last.arguments.sublist(3), [
        'research-doc',
        'a/b.md',
      ]);
      expect((await api.skillDoc('scaffold')).name, 'scaffold');
      expect(runner.calls.last.arguments.sublist(3), ['skill-doc', 'scaffold']);
    });

    test(
      'a path with spaces and quotes goes through as one argument',
      () async {
        runner.answer = (_) => _ok({'path': 'p', 'text': ''});
        await api.researchDoc('my notes/"x".md');
        expect(runner.calls.single.arguments.last, 'my notes/"x".md');
      },
    );

    test('the inbox is a list of names', () async {
      runner.answer = (_) => _ok(['a.md', 'b.md']);
      expect(await api.inbox(), ['a.md', 'b.md']);
    });
  });

  group('failures', () {
    test('nils\'s own words are the message, without the prefix', () async {
      runner.answer = (_) => _failed('error: no such document\n');
      await expectLater(
        api.researchDoc('x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'no such document',
          ),
        ),
      );
    });

    test('a failure that says nothing gives the exit code', () async {
      runner.answer = (_) => _failed('', 2);
      await expectLater(
        api.inbox(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'nils exited with code 2',
          ),
        ),
      );
    });

    test('output that is not JSON is an error', () async {
      runner.answer = (_) => ProcessResult(1, 0, 'Traceback...', '');
      await expectLater(api.inbox(), throwsA(isA<ApiException>()));
    });

    test('a program that cannot start is named', () async {
      runner.failure = const ProcessException('uv', [], 'No such file', 2);
      await expectLater(
        api.inbox(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('could not run uv'),
          ),
        ),
      );
    });
  });

  group('upload', () {
    test('stages a file called name through `nils inbox add`', () async {
      String? seenName;
      String? seenText;
      runner.answer = (arguments) {
        final path = arguments.last;
        seenName = path.split('/').last;
        seenText = File(path).readAsStringSync();
        return ProcessResult(1, 0, 'staged my-notes.md\n', '');
      };
      await api.upload('My Notes.md', utf8.encode('# hi\n'));
      expect(runner.calls.single.arguments.sublist(0, 4), [
        'run',
        'nils',
        'inbox',
        'add',
      ]);
      expect(seenName, 'My Notes.md');
      expect(seenText, '# hi\n');
    });

    test('removes its scratch file whether or not nils took it', () async {
      String? path;
      runner.answer = (arguments) {
        path = arguments.last;
        return _failed('error: note.md is already staged');
      };
      await expectLater(
        api.upload('note.md', [35]),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'note.md is already staged',
          ),
        ),
      );
      expect(File(path!).existsSync(), isFalse);
      expect(Directory(File(path!).parent.path).existsSync(), isFalse);
    });
  });

  group('NilsCommand', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('everything-repo-'));
    tearDown(() => dir.deleteSync(recursive: true));

    Directory repoAt(String path) =>
        Directory('${dir.path}/$path/storage/data/research')
          ..createSync(recursive: true);

    test('finds the checkout above a start directory', () {
      repoAt('nils');
      final deep = Directory('${dir.path}/nils/app/lib')
        ..createSync(recursive: true);
      expect(
        NilsCommand.findRepo([deep])?.path,
        Directory('${dir.path}/nils').absolute.path,
      );
    });

    test('finds a sibling named nils', () {
      repoAt('nils');
      final here = Directory('${dir.path}/everything')..createSync();
      expect(
        NilsCommand.findRepo([here])?.path,
        Directory('${dir.path}/nils').absolute.path,
      );
    });

    test('finds nothing when there is no checkout', () {
      final here = Directory('${dir.path}/elsewhere')..createSync();
      expect(NilsCommand.findRepo([here]), isNull);
    });

    test('uses the checkout\'s virtualenv when it has one', () {
      final repo = Directory('${dir.path}/nils')..createSync();
      expect(NilsCommand.forRepo(repo).executable, 'uv');
      File('${repo.path}/.venv/bin/nils').createSync(recursive: true);
      final command = NilsCommand.forRepo(repo);
      expect(command.executable, '${repo.path}/.venv/bin/nils');
      expect(command.arguments(['view', 'inbox']), ['view', 'inbox']);
    });
  });
}
