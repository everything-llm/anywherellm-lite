import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/settings/settings_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<String> labels(String query, {bool configured = true}) => [
    for (final hit in searchSettings(query, configured: configured)) hit.label,
  ];

  test('a page is found by its name, its line or one of its fields', () {
    expect(labels('transcription'), ['Transcription']);
    expect(labels('embedder'), ['Document search model']);
    expect(labels('anonymous'), ['Privacy and data']);
    // A page named by its own words has no field to show.
    expect(searchSettings('chat model', configured: true).first.field, isNull);
    final key = searchSettings('API key', configured: true);
    expect(key.first.page, SettingsPage.connection);
    expect(key.first.field, 'API key');
  });

  test('a provider\'s fields are searched too, and name the page', () {
    final hit = searchSettings('context window', configured: true).first;
    expect(hit.page, SettingsPage.chatModel);
    expect(hit.field, 'Context window');
  });

  test('a page of AnythingLLM\'s web page is found, after the app\'s', () {
    final hits = searchSettings('security', configured: true);
    expect(hits.last.label, 'Security');
    expect(hits.last.page, isNull);
    expect(labels('scheduled jobs'), ['Scheduled jobs']);
  });

  test(
    'the Server page never matches, and with no server only this device does',
    () {
      expect(labels('server'), isNot(contains('Server')));
      expect(labels('chat', configured: false), ['Appearance', 'Chat']);
      expect(labels('security', configured: false), isEmpty);
      expect(labels('   '), isEmpty);
    },
  );
}
