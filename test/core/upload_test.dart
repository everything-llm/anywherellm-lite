import 'package:anywherellm/core/upload.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
