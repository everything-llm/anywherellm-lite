// The everythingllm browser as a chat sees it: the steps its skills take, and the live card
// that shows a chat's tab.

import 'dart:convert';

import 'markdown.dart';

/// A browser tab's live card in an answer: its [image], the [page] it links to (the take-over
/// view while the browser runs), and its [title].
class BrowserCard {
  const BrowserCard({
    required this.image,
    required this.page,
    required this.title,
  });

  final Uri image;
  final Uri page;
  final String title;
}

/// The browser cards in the Markdown [markdown], in order: each linked image of a tab's card,
/// `/_live/browser/bw-<id>.jpg` linking to `/_live/browser/bw-<id>`, on the [server]'s host. A
/// login request's card is not one.
List<BrowserCard> browserCards(String markdown, {required Uri? server}) {
  if (server == null || !markdown.contains('/_live/browser/')) return const [];
  return [
    for (final (:image, :alt, :link) in linkedImagesIn(markdown))
      if (_tab(image, server, _card) case final tab?
          when _tab(link, server, _page) == tab)
        BrowserCard(image: image, page: link, title: alt),
  ];
}

/// Whether [href] is a browser card's page on the [server]'s host, which opens the tab's
/// take-over view.
bool isBrowserPage(String href, Uri? server) {
  final uri = Uri.tryParse(href);
  return uri != null && server != null && _tab(uri, server, _page) != null;
}

final _card = RegExp(r'^/_live/browser/(bw-[0-9a-f]{16})\.jpg$');
final _page = RegExp(r'^/_live/browser/(bw-[0-9a-f]{16})/?$');

/// The tab whose card or page ([pattern]) [uri] is, on the [server]'s host, or null.
String? _tab(Uri uri, Uri server, RegExp pattern) =>
    uri.host == server.host ? pattern.firstMatch(uri.path)?.group(1) : null;

/// Whether [tool] is one of the everythingllm browser's skills.
bool isBrowserTool(String? tool) => _browserTools.contains(tool);

/// What a [call] of one of the everythingllm browser's skills does, in words, read from its
/// JSON arguments, or null for any other tool. A step never says what is typed.
String? browserStep(({String name, String args}) call) {
  if (!isBrowserTool(call.name)) return null;
  final args = _arguments(call.args);
  String? text(String key) => switch (args[key]) {
    final String value when value.trim().isNotEmpty => value.trim(),
    _ => null,
  };
  return switch (call.name) {
    'browse' => switch (Uri.tryParse(text('url') ?? '')?.host) {
      final String host when host.isNotEmpty => 'Opening $host',
      _ => 'Opening a page',
    },
    'browser-act' => _acts[text('action')] ?? 'Using the browser',
    'browser-read' => switch (text('find')) {
      final String find => 'Looking for "$find"',
      null => 'Reading the page',
    },
    'browser-handoff' =>
      args['done'] == true || args['done'] == 'true'
          ? 'Taking the browser back'
          : 'Handing the browser to you',
    _ => _logins[text('action')] ?? 'Using a saved login',
  };
}

const _browserTools = {
  'browse',
  'browser-act',
  'browser-read',
  'browser-handoff',
  'browser-login',
};

const _acts = {
  'click': 'Clicking',
  'fill': 'Typing into a field',
  'type': 'Typing into a field',
  'press': 'Pressing a key',
  'select': 'Choosing an option',
  'check': 'Ticking a box',
  'hover': 'Pointing at the page',
  'scroll': 'Scrolling',
  'back': 'Going back',
  'forward': 'Going forward',
  'reload': 'Reloading the page',
  'wait': 'Waiting for the page',
};

const _logins = {
  'list': 'Looking through the saved logins',
  'login': 'Signing in with a saved login',
  'code': 'Filling a 2FA code',
  'passkey': 'Signing in with a passkey',
  'ask': 'Asking you for a login',
};

/// A tool call's JSON arguments, or none when they are not a JSON object.
Map<String, Object?> _arguments(String json) {
  try {
    if (jsonDecode(json) case final Map<String, Object?> args) return args;
  } on FormatException {
    // Arguments that do not parse leave the step to the tool's name.
  }
  return const {};
}
