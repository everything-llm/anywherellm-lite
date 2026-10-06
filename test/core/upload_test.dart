import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/core/upload.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

void main() {
  group('extensionProblem', () {
    test('is null for a type the server reads, in any case', () {
      expect(extensionProblem('Notes.MD', {'.md'}), isNull);
    });

    test('names a type the server does not read', () {
      expect(
        extensionProblem('a.exe', {'.md'}),
        'the server does not read .exe files',
      );
    });

    test('says when there is no extension', () {
      expect(extensionProblem('Makefile', {'.md'}), contains('no extension'));
      expect(extensionProblem('.bashrc', {'.md'}), contains('no extension'));
    });

    test('lets the server decide when it has not said', () {
      expect(extensionProblem('a.exe', null), isNull);
    });
  });

  test(
    'sourceExt is four upper-case letters at most, and agrees with the check',
    () {
      expect(sourceExt('note.md'), 'MD');
      expect(sourceExt('note.markdown'), 'MARK');
      expect(sourceExt('README'), 'FILE');
      expect(sourceExt('.bashrc'), 'FILE');
      expect(sourceExt('Q3 roadmap.pdf'), 'PDF');
      expect(sourceExt('Jobs for a .NET/React Candidate, 2026'), 'FILE');
      expect(sourceExt('Version 2.0 notes'), 'FILE');
    },
  );

  group('linkProblem', () {
    test('is null for a web address', () {
      expect(linkProblem(' https://example.com/page '), isNull);
      expect(linkProblem('http://intranet/wiki'), isNull);
    });

    test('names an address that is not http or https', () {
      expect(
        linkProblem('example.com'),
        'a link starts with https:// or http://',
      );
      expect(
        linkProblem('ftp://example.com'),
        'a link starts with https:// or http://',
      );
    });

    test('names an address with no site', () {
      expect(linkProblem('https://'), 'the link has no site in it');
    });
  });

  group('DocMeta', () {
    test(
      'keeps the fields that are not blank, trimmed, under the server keys',
      () {
        expect(
          const DocMeta(
            title: ' Plan ',
            author: '',
            description: '  ',
            source: 'Ada',
          ).toJson(),
          {'title': 'Plan', 'docSource': 'Ada'},
        );
        expect(const DocMeta(description: ' ').isEmpty, isTrue);
      },
    );
  });

  test('sendEach hands each file its own details', () async {
    final llm = FakeAnythingLlm();
    await sendEach(llm, [
      UploadFile(
        name: 'a.md',
        read: () async => [1],
        meta: const DocMeta(author: 'Ada'),
      ),
      UploadFile(name: 'b.md', read: () async => [2]),
    ], folder: 'notes');
    expect(llm.metaOf['notes/a.md.json']?.author, 'Ada');
    expect(llm.metaOf['notes/b.md.json']?.isEmpty, isTrue);
  });
}
