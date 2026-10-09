import '../../core/providers.dart';
import 'settings_pages.dart';

/// A page that matched a search of Settings: an app page, or one of [webPages], and the field
/// that matched when the page's own name and line did not.
class SettingsHit {
  const SettingsHit.page(SettingsPage this.page, {this.field}) : web = null;
  const SettingsHit.web(WebPage this.web, {this.field}) : page = null;

  final SettingsPage? page;
  final WebPage? web;

  /// The name of the field that matched, or null when the page's name or line did.
  final String? field;

  String get label => page?.label ?? web!.label;
}

/// The names of the fields on each page that is not a provider's, as a search sees them.
const _fields = {
  SettingsPage.connection: [
    'Address',
    'API key',
    'Server password',
    'Background answers',
  ],
  SettingsPage.appearance: ['Theme', 'Chat text size'],
  SettingsPage.chat: [
    'Send dictation when I stop talking',
    'Read answers aloud',
    'Spellcheck the message',
    'Follow a streaming answer',
    'Show answer details',
  ],
  SettingsPage.chats: ['Export'],
  SettingsPage.embeds: ['Allowed sites', 'Chats per day', 'Chats per visit'],
  SettingsPage.privacy: ['Anonymous telemetry'],
};

/// The providers each provider page chooses among.
const _providers = {
  SettingsPage.chatModel: [chatProviders],
  SettingsPage.searchModel: [embedderProviders],
  SettingsPage.storage: [vectorProviders],
  SettingsPage.images: [imageProviders],
  SettingsPage.voice: [speechToTextProviders, textToSpeechProviders],
  SettingsPage.transcription: [transcriptionProviders],
};

/// The names of [page]'s fields: its choosers, and what each provider it offers reads.
Iterable<String> fieldNames(SettingsPage page) sync* {
  yield* _fields[page] ?? const [];
  for (final setting in _providers[page] ?? const <ProviderSetting>[]) {
    yield setting.label;
    for (final provider in setting.providers) {
      for (final field in provider.fields) {
        yield field.label;
      }
    }
  }
}

/// The pages whose name or line holds [query], or one of whose fields' names does, in the order
/// Settings lists them and then [webPages]. The Server page is only a list of the others, so it
/// never matches; while no server is saved, only the pages about this device do.
List<SettingsHit> searchSettings(String query, {required bool configured}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  bool holds(String text) => text.toLowerCase().contains(needle);
  final hits = <SettingsHit>[];
  for (final page in SettingsPage.values) {
    if (page == SettingsPage.server || (page.needsServer && !configured)) {
      continue;
    }
    if (holds(page.label) || holds(page.about)) {
      hits.add(SettingsHit.page(page));
    } else if (fieldNames(page).where(holds).firstOrNull case final field?) {
      hits.add(SettingsHit.page(page, field: field));
    }
  }
  if (configured) {
    for (final web in webPages) {
      if (holds(web.label) || holds(web.about)) hits.add(SettingsHit.web(web));
    }
  }
  return hits;
}
