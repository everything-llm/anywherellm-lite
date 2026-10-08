/// The groups Settings lists its pages under, in order.
enum SettingsGroup {
  app('AnywhereLLM'),
  providers('AI providers'),
  data('Workspaces and data'),
  tools('Tools'),
  privacy('Security and privacy'),
  advanced('Advanced');

  const SettingsGroup(this.label);
  final String label;
}

/// The pages of Settings, in the order its list shows them.
enum SettingsPage {
  connection(
    SettingsGroup.app,
    'Connection',
    'How this device reaches AnythingLLM. The address, key and password stay in this '
        'device\'s keyring.',
    essential: true,
    needsServer: false,
  ),
  appearance(
    SettingsGroup.app,
    'Appearance',
    'How AnywhereLLM looks on this device.',
    essential: true,
    needsServer: false,
  ),
  chat(
    SettingsGroup.app,
    'Chat',
    'How the chat behaves on this device.',
    essential: true,
    needsServer: false,
  ),
  server(
    SettingsGroup.providers,
    'Server',
    'What AnythingLLM runs with.',
    phoneOnly: true,
  ),
  chatModel(
    SettingsGroup.providers,
    'Chat model',
    'The provider and model every workspace uses unless its own settings name another.',
    essential: true,
  ),
  searchModel(
    SettingsGroup.providers,
    'Document search model',
    'Prepares your documents so answers can search them. AnythingLLM calls this the embedder.',
  ),
  storage(
    SettingsGroup.providers,
    'Document storage',
    'Where the searchable copy of your documents is kept. AnythingLLM calls this the vector '
        'database.',
  ),
  images(
    SettingsGroup.providers,
    'Image generation',
    'Used by the /img command and the Generate images skill.',
  ),
  voice(
    SettingsGroup.providers,
    'Voice and speech',
    'The server\'s own listening and speaking, used by the web UI.',
  ),
  transcription(
    SettingsGroup.providers,
    'Transcription',
    'Turns audio and video files into text when they are added.',
  ),
  chats(
    SettingsGroup.data,
    'Workspace chats',
    'Every chat recorded on the server.',
  ),
  embeds(
    SettingsGroup.tools,
    'Website chat widgets',
    'Chat widgets other sites can show, each tied to one workspace. AnythingLLM calls these '
        'chat embeds.',
  ),
  privacy(
    SettingsGroup.privacy,
    'Privacy and data',
    'Where your questions and files go.',
    essential: true,
  ),
  json(
    SettingsGroup.advanced,
    'Server settings as JSON',
    'Every setting the server takes from the app, written to its .env. Keys and passwords are '
        'left out.',
  );

  const SettingsPage(
    this.group,
    this.label,
    this.about, {
    this.essential = false,
    this.needsServer = true,
    this.phoneOnly = false,
  });

  final SettingsGroup group;
  final String label;

  /// The line under the page's title.
  final String about;

  /// Whether the page shows while Settings lists only the essentials.
  final bool essential;

  /// Whether the page is about the server, and so shows only once one is saved.
  final bool needsServer;

  /// Whether only a phone has the page: [server], which lists the server's pages there.
  final bool phoneOnly;

  /// The page a phone's back arrow goes to from this one: [server] from a page about the
  /// server, or null, the list, from the others.
  SettingsPage? get phoneParent =>
      needsServer && this != server ? server : null;
}
