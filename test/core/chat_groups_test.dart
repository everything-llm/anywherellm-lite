import 'package:anywherellm/core/chat_groups.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _slugs(List<Thread> threads) => [for (final t in threads) t.slug];

void main() {
  // The server lists a workspace's chats oldest made first.
  final threads = [
    for (final s in ['a', 'b', 'c', 'd', 'e']) Thread(slug: s, name: s),
  ];

  test('pinned, then last used, then the rest newest made first', () {
    final groups = groupChats(threads, ['b'], ['b', 'd', 'a']);
    expect(_slugs(groups.pinned), ['b']);
    expect(_slugs(groups.recent), ['d', 'a']);
    expect(_slugs(groups.rest), ['e', 'c']);
  });

  test('pins of chats that are gone count for nothing', () {
    final groups = groupChats(threads, ['gone'], const ['gone']);
    expect(groups.pinned, isEmpty);
    expect(groups.recent, isEmpty);
    expect(_slugs(groups.rest), ['e', 'd', 'c', 'b', 'a']);
  });
}
