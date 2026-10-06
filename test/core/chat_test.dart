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

  group('splitReasoning', () {
    test('takes a think block out of the answer', () {
      final split = splitReasoning('<think>Red, clearly.</think>red');
      expect(split.reasoning, 'Red, clearly.');
      expect(split.answer, 'red');
      expect(split.thinking, isFalse);
    });

    test('an open block is reasoning still arriving', () {
      final split = splitReasoning('<think>Let me see');
      expect(split.reasoning, 'Let me see');
      expect(split.answer, isEmpty);
      expect(split.thinking, isTrue);
    });

    test('the start of an opening tag is held back', () {
      for (final partial in ['<', '<th', '<think', '  <thinki']) {
        final split = splitReasoning(partial);
        expect(split.answer, isEmpty, reason: partial);
        expect(split.thinking, isTrue, reason: partial);
      }
    });

    test('takes thinking tags and several blocks', () {
      final split = splitReasoning(
        '<thinking>One.</thinking>A <think>Two.</think>B',
      );
      expect(split.reasoning, 'One.\n\nTwo.');
      expect(split.answer, 'A B');
    });

    test('text without a block is all answer', () {
      final split = splitReasoning('Use `a < b` here.');
      expect(split.reasoning, isEmpty);
      expect(split.answer, 'Use `a < b` here.');
      expect(split.thinking, isFalse);
    });
  });

  group('chat modes', () {
    test('each is the server\'s value, and an unknown one is none', () {
      expect(
        [
          for (final v in ['automatic', 'chat', 'query', 'agent', null])
            ChatMode.fromServer(v),
        ],
        [ChatMode.automatic, ChatMode.chat, ChatMode.query, null, null],
      );
      expect(
        [for (final m in ChatMode.values) m.label],
        ['Agent', 'Chat', 'Query'],
      );
    });

    test('an agent\'s thoughts read as plain status lines', () {
      expect(
        agentStatus('@agent is executing `web-browsing` tool {\n "q": 1\n}'),
        'Running web-browsing',
      );
      expect(
        agentStatus('@agent: I found 47 results - reviewing.'),
        'I found 47 results - reviewing.',
      );
      expect(agentStatus('Thinking about it\nmore'), 'Thinking about it');
    });
  });
}
