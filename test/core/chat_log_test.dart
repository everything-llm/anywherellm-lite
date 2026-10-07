import 'package:anywherellm/core/chat_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a chat\'s time is said against now', () {
    final now = DateTime(2026, 10, 7, 12);
    expect(sentText(DateTime(2026, 10, 7, 9, 5), now), 'Today 09:05');
    expect(sentText(DateTime(2026, 10, 6, 23), now), 'Yesterday');
    expect(sentText(DateTime(2026, 10, 3), now), '3 Oct');
    expect(sentText(DateTime(2025, 12, 31), now), '31 Dec 2025');
  });

  test('a page the server answers oddly reads as empty', () {
    expect(ChatLog.fromJson(null).chats, isEmpty);
    expect(ChatLog.fromJson({'chats': 'no'}).more, isFalse);
  });
}
