import 'dart:convert';

import 'package:anywherellm/core/notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chatTargetOf', () {
    test('a ready answer\'s notification opens its chat', () {
      final payload = answerReadyPayload(
        title: 'Podcasts',
        body: 'Here is the game.',
        slug: 'cloud',
        thread: 't-1',
      );
      expect(chatTargetOf(payload), const ChatTarget('cloud', 't-1'));
    });

    test('a payload that names no chat opens nothing', () {
      for (final data in [
        {'workspace': 'cloud'},
        {'workspace': '', 'thread': 't-1'},
        {'workspace': 'cloud', 'thread': ''},
        {'onClickUrl': '/settings/scheduled-jobs/4/runs/9'},
      ]) {
        expect(chatTargetOf(jsonEncode({'title': 'x', 'data': data})), isNull);
      }
      expect(chatTargetOf('not json'), isNull);
    });
  });
}
