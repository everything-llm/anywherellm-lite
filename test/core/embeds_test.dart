import 'package:anywherellm/core/embeds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an embed reads as the server lists it', () {
    final embed = Embed.fromJson({
      'id': 1,
      'uuid': 'e-1',
      'enabled': true,
      'chat_mode': 'chat',
      'workspace': {'id': 3, 'name': 'Q3 planning'},
      'chat_count': 4,
    });
    expect(
      (embed.uuid, embed.workspace, embed.mode, embed.enabled, embed.chats),
      ('e-1', 'Q3 planning', EmbedMode.chat, true, 4),
    );
    expect(Embed.fromJson({'chat_mode': 'automatic'}).mode, EmbedMode.query);
  });

  test('a new embed sends only what was given', () {
    expect(const NewEmbed(workspaceSlug: 'q3').toJson(), {
      'workspace_slug': 'q3',
      'chat_mode': 'query',
    });
    expect(
      NewEmbed(
        workspaceSlug: 'q3',
        mode: EmbedMode.chat,
        sites: sitesOf(' example.com, docs.example.com\nblog.example.com '),
        chatsPerDay: 100,
      ).toJson(),
      {
        'workspace_slug': 'q3',
        'chat_mode': 'chat',
        'allowlist_domains': [
          'example.com',
          'docs.example.com',
          'blog.example.com',
        ],
        'max_chats_per_day': 100,
      },
    );
  });

  test(
    'an embed chat\'s answer is the text in its JSON, or the text itself',
    () {
      final kept = EmbedChat.fromJson({
        'session_id': 's-1',
        'prompt': 'Hi',
        'response': '{"text":"Hello there","type":"chat","sources":[]}',
        'createdAt': '2026-10-01T12:00:00Z',
      });
      expect(
        (kept.session, kept.question, kept.answer),
        ('s-1', 'Hi', 'Hello there'),
      );
      expect(kept.at, DateTime.utc(2026, 10, 1, 12));
      expect(EmbedChat.fromJson({'response': 'Plain'}).answer, 'Plain');
    },
  );

  test('the HTML points at the server\'s own origin', () {
    expect(
      embedSnippet(Uri.parse('https://owen.example.ts.net:3001/'), 'e-1'),
      '<script\n'
      '  data-embed-id="e-1"\n'
      '  data-base-api-url="https://owen.example.ts.net:3001/api/embed"\n'
      '  src="https://owen.example.ts.net:3001/embed/anythingllm-chat-widget.min.js">\n'
      '</script>',
    );
  });

  test('the HTML keeps a server\'s base path', () {
    expect(
      embedSnippet(Uri.parse('https://host.example/anythingllm/'), 'e-1'),
      contains(
        'data-base-api-url="https://host.example/anythingllm/api/embed"',
      ),
    );
  });
}
