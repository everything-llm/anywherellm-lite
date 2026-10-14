import 'dart:typed_data';

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

    test('never splits an emoji made of several code points', () {
      const family = '👨‍👩‍👧';
      expect(
        defaultTitle('${'a' * 40}$family and more'),
        '${'a' * 40}$family…',
      );
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
      expect(Attachment.of('a.gif', Uint8List(0)).isImage, isTrue);
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

    test('a pasted picture is named by its type, apart from those taken', () {
      expect(pastedImageName('image/png', const []), 'Pasted image.png');
      expect(
        pastedImageName('image/JPEG', [
          'Pasted image.jpg',
          'Pasted image 2.jpg',
        ]),
        'Pasted image 3.jpg',
      );
      expect(
        attachmentMime(pastedImageName('image/webp', const [])!),
        'image/webp',
      );
    });

    test('a pasted file that is no picture the server takes has no name', () {
      expect(pastedImageName('image/heic', const []), isNull);
      expect(pastedImageName('text/plain', const []), isNull);
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

    test('a tag written as code is answer, not reasoning', () {
      for (final text in [
        'DeepSeek wraps its reasoning in `<think>` and `</think>` tags, then answers.',
        'Use the `<think>` tag to start. More text...',
        'Write:\n```\n<think>plan</think>\n```\nDone.',
      ]) {
        final split = splitReasoning(text);
        expect(split.answer, text, reason: text);
        expect(split.reasoning, isEmpty, reason: text);
        expect(split.thinking, isFalse, reason: text);
      }
    });

    test('a block after code is still reasoning', () {
      final split = splitReasoning('`a` <think>Hm.</think>b');
      expect(split.reasoning, 'Hm.');
      expect(split.answer, '`a` b');
    });

    test('a finished answer keeps a bare tag that never closed', () {
      const text = 'Wrap the output in a <think> tag. Then parse the rest.';
      expect(splitReasoning(text).answer, text);
      expect(splitReasoning(text).thinking, isFalse);
      final streaming = splitReasoning(text, streaming: true);
      expect(streaming.answer, 'Wrap the output in a');
      expect(streaming.thinking, isTrue);
    });

    test(
      'a finished answer that opens with an unclosed block is reasoning',
      () {
        final split = splitReasoning('<think>Ran out of tokens');
        expect(split.reasoning, 'Ran out of tokens');
        expect(split.answer, isEmpty);
      },
    );

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
    });

    test('each is named in plain words where people choose it', () {
      expect(
        [for (final m in ChatMode.values) m.title],
        ['Files, knowledge & tools', 'Files & knowledge', 'Files only'],
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

  test('an agent model failure is told from an answer', () {
    expect(
      modelFailure('  The agent model failed to respond: 400 bad input\n'),
      'The agent model failed to respond: 400 bad input',
    );
    expect(
      modelFailure('It said "The agent model failed to respond" once.'),
      isNull,
    );
    expect(modelFailure(''), isNull);
  });

  test('only web and mail links open', () {
    expect(
      [
        for (final href in [
          'https://example.com/a',
          'http://example.com',
          'mailto:ada@example.com',
          'javascript:alert(1)',
          'file:///etc/passwd',
          '/relative/path',
          'myapp://open',
          'https://',
          'mailto:',
        ])
          openableLink(href)?.toString(),
      ],
      [
        'https://example.com/a',
        'http://example.com',
        'mailto:ada@example.com',
        null,
        null,
        null,
        null,
        null,
        null,
      ],
    );
  });

  test(
    'a path from the root is on the server, as AnythingLLM\'s chat reads it',
    () {
      final server = Uri.parse('https://owen.example.ts.net:3001/');
      expect(
        openableLink('/browser-lean/3kQ.html', server: server).toString(),
        'https://owen.example.ts.net:3001/browser-lean/3kQ.html',
      );
      expect(
        onServer(
          Uri.parse('/browser-lean/3kQ-card.jpg?v=lq2m1'),
          server,
        ).toString(),
        'https://owen.example.ts.net:3001/browser-lean/3kQ-card.jpg?v=lq2m1',
      );
      expect(openableLink('relative/path', server: server), isNull);
      expect(openableLink('/relative/path'), isNull);
      expect(
        onServer(Uri.parse('https://example.com/a.png'), server).host,
        'example.com',
      );
    },
  );

  group('loadableImage', () {
    final server = Uri.parse('https://owen.example.ts.net:3001');
    bool loads(String image, {Uri? from}) =>
        loadableImage(Uri.parse(image), from);

    test('the server\'s own host over https, on any port', () {
      expect(
        loads('https://owen.example.ts.net:3001/a.png', from: server),
        isTrue,
      );
      expect(
        loads('https://owen.example.ts.net:8080/card.png', from: server),
        isTrue,
      );
    });

    test('never another host, nor with no server', () {
      expect(loads('https://example.com/a.png', from: server), isFalse);
      expect(loads('https://owen.example.ts.net/a.png'), isFalse);
    });

    test('over http only on a private network', () {
      final public = Uri.parse('https://ai.example.com');
      final home = Uri.parse('http://box.local:3001');
      expect(loads('http://ai.example.com/a.png', from: public), isFalse);
      expect(loads('http://box.local:8080/a.png', from: home), isTrue);
    });
  });
}
