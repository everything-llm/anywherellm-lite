import '../../core/providers.dart';

/// The pages of Settings. Connection, Appearance and Chat are about this device; Server lists
/// the pages about AnythingLLM, which open from it.
enum SettingsPage {
  connection(
    'Connection',
    'How this device reaches AnythingLLM. The address, key and password stay in this '
        'device\'s keyring.',
    needsServer: false,
  ),
  appearance(
    'Appearance',
    'How AnywhereLLM looks on this device.',
    needsServer: false,
  ),
  chat('Chat', 'How the chat behaves on this device.', needsServer: false),
  server(
    'Server',
    'What AnythingLLM runs with. A change here changes the server for every device and '
        'workspace.',
  ),
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

  const SettingsPage(this.label, this.about, {this.needsServer = true});

  final String label;

  /// The line under the page's title.
  final String about;

  /// Whether the page is about the server, and so shows only once one is saved.
  final bool needsServer;

  /// The page this one is reached from and goes back to: [server] for a page about the server
  /// other than [server] itself, or null, the list, for the others.
  SettingsPage? get parent => needsServer && this != server ? server : null;
}

/// A page of AnythingLLM's own web page that the app does not have, which Settings links to.
class WebPage {
  const WebPage(this.label, this.about);

  final String label;

  /// What the page is for, in a line.
  final String about;
}

/// AnythingLLM's pages the app leaves to its web page, in the order the Server page lists them.
const webPages = [
  WebPage(
    'Document splitting',
    'How new documents are cut into passages before they are stored. AnythingLLM calls this '
        'the text splitter.',
  ),
  WebPage(
    'Skills and tools',
    'What answers may do when a chat is set to use tools. AnythingLLM calls these agent '
        'skills.',
  ),
  WebPage(
    'Default instructions',
    'What a new workspace starts with. AnythingLLM calls this the system prompt. It can use '
        'variables such as {date}.',
  ),
  WebPage(
    'Instruction variables',
    'Values the instructions fill in, written in braces like {date}. AnythingLLM calls these '
        'prompt variables.',
  ),
  WebPage(
    'Scheduled jobs',
    'Prompts that run on a schedule and keep their results.',
  ),
  WebPage('Activity log', 'What happened on the server, newest first.'),
  WebPage(
    'API keys',
    'Keys for programs that talk to AnythingLLM. AnythingLLM calls this the developer API.',
  ),
  WebPage('Security', 'Who can open this server.'),
];

/// The providers each provider page chooses among, which the page draws and a search reads the
/// names of.
const providerPages = {
  SettingsPage.chatModel: [chatProviders],
  SettingsPage.searchModel: [embedderProviders],
  SettingsPage.storage: [vectorProviders],
  SettingsPage.images: [imageProviders],
  SettingsPage.voice: [speechToTextProviders, textToSpeechProviders],
  SettingsPage.transcription: [transcriptionProviders],
};
