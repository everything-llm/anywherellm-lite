import 'package:anywherellm/core/chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('defaultTitle', () {
    test('is the first line of the message', () {
      expect(defaultTitle('  What is due?\nAnd when?'), 'What is due?');
    });

    test('cuts a long line to 42 characters with an ellipsis', () {
      final title = defaultTitle('a' * 60);
      expect(title.length, 42);
      expect(title, endsWith('…'));
    });

    test('never splits an emoji', () {
      expect(defaultTitle('${'a' * 40}😀 and more'), '${'a' * 40}😀…');
    });

    test('keeps a line of exactly 42 characters whole', () {
      expect(defaultTitle('b' * 42), 'b' * 42);
    });

    test('a blank message leaves the chat named New chat', () {
      expect(defaultTitle('   '), newChatName);
    });
  });

  group('attachments', () {
    test('a picture is typed by its extension, in any case', () {
      expect(attachmentMime('photo.JPG'), 'image/jpeg');
      expect(attachmentMime('a.webp'), 'image/webp');
      expect(Attachment.of('a.gif', const []).isImage, isTrue);
    });

    test('any other file, or none, is a document', () {
      expect(attachmentMime('report.pdf'), documentMime);
      expect(attachmentMime('Makefile'), documentMime);
      expect(attachmentMime('.png'), documentMime);
    });

    test('a file over the cap is refused with its size', () {
      expect(attachmentProblem('a.pdf', maxAttachmentBytes), isNull);
      expect(
        attachmentProblem('a.pdf', maxAttachmentBytes + 1),
        startsWith('a.pdf is 20.0 MB'),
      );
    });
  });
}
