/// The pages of Settings. Connection, Appearance and Chat are about this device; Server says what
/// AnythingLLM runs with and opens Privacy and data, and Memory sits beside it.
enum SettingsPage {
  connection('Connection', null, needsServer: false),
  appearance('Appearance', null, needsServer: false),
  chat('Chat', null, needsServer: false),
  shortcuts(
    'Shortcuts',
    'Type `/` in a message, or tap + beside it.',
    needsServer: false,
  ),
  memory('Memory', null),
  server('Server', null),
  privacy('Privacy and data', 'Where your questions and files go.');

  const SettingsPage(this.label, this.about, {this.needsServer = true});

  final String label;

  /// The line under the page's title, or null for a page the Lite prototype draws without one.
  final String? about;

  /// Whether the page is about the server, and so shows only once one is saved.
  final bool needsServer;

  /// The page this one is reached from and goes back to: [server] for [privacy], or null, the
  /// list, for the others.
  SettingsPage? get parent => switch (this) {
    privacy => server,
    shortcuts => chat,
    _ => null,
  };
}
