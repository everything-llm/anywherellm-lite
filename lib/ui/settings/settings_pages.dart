import '../../core/providers.dart';

/// The pages of Settings. Connection, Appearance and Chat are about this device; Server lists
/// the pages about AnythingLLM, which open from it, and Memory and System files sit beside it.
enum SettingsPage {
  connection('Connection', null, needsServer: false),
  appearance('Appearance', null, needsServer: false),
  chat('Chat', null, needsServer: false),
  memory('Memory', null),
  systemFiles('System files', null, ownsPage: true),
  server('Server', null),
  chatModel(
    'Chat model',
    'The provider and model every workspace uses unless its own settings name another.',
  ),
  searchModel(
    'Document search model',
    'Prepares your documents so answers can search them. AnythingLLM calls this the embedder.',
  ),
  storage(
    'Document storage',
    'Where the searchable copy of your documents is kept. AnythingLLM calls this the vector '
        'database.',
  ),
  images(
    'Image generation',
    'Used by the /img command and the Generate images skill.',
  ),
  voice(
    'Voice and speech',
    'The server\'s own listening and speaking, used by the web UI.',
  ),
  transcription(
    'Transcription',
    'Turns audio and video files into text when they are added.',
  ),
  chats('Workspace chats', 'Every chat recorded on the server.'),
  embeds(
    'Website chat widgets',
    'Chat widgets other sites can show, each tied to one workspace. AnythingLLM calls these '
        'chat embeds.',
  ),
  privacy('Privacy and data', 'Where your questions and files go.'),
  json(
    'Server settings as JSON',
    'Every setting the server takes from the app, written to its .env. Keys and passwords are '
        'left out.',
  );

  const SettingsPage(
    this.label,
    this.about, {
    this.needsServer = true,
    this.ownsPage = false,
  });

  final String label;

  /// The line under the page's title, or null for a page the design canvas draws without one.
  final String? about;

  /// Whether the page is about the server, and so shows only once one is saved.
  final bool needsServer;

  /// Whether the page draws its own header and scrolling, as one whose title changes does.
  final bool ownsPage;

  /// The page this one is reached from and goes back to: [server] for a page about the server
  /// other than [server] itself, [memory] and [systemFiles], or null, the list, for the others.
  SettingsPage? get parent =>
      needsServer && !const [server, memory, systemFiles].contains(this)
      ? server
      : null;
}

/// The providers each provider page chooses among, which the page draws.
const providerPages = {
  SettingsPage.chatModel: [chatProviders],
  SettingsPage.searchModel: [embedderProviders],
  SettingsPage.storage: [vectorProviders],
  SettingsPage.images: [imageProviders],
  SettingsPage.voice: [speechToTextProviders, textToSpeechProviders],
  SettingsPage.transcription: [transcriptionProviders],
};
