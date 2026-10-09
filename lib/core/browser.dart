// The everythingllm browser as a chat sees it: the steps its skills take, and the live card
// that shows a chat's tab.

import 'dart:convert';

import 'copy.dart';
import 'host_routes.dart';
import 'markdown.dart';

/// A card of the everythingllm browser in an answer: a tab's live card, whose [page] is the
/// tab's take-over view while the browser runs, or, when [login], a login request's card, whose
/// [page] is the form that saves the login. [image] is the card itself and [title] its
/// description.
class BrowserCard {
  const BrowserCard({
    required this.image,
    required this.page,
    required this.title,
    this.login = false,
  });

  final Uri image;
  final Uri page;
  final String title;
  final bool login;
}

/// A chat's browser tab as the server reports it to a client with a developer key: [page] is
/// its take-over view, [state] who has it (`working`, `idle`, `waiting`, `user` or `closed`),
/// [title] what the card names the page, [site] whose it is, never its address, and [last] what
/// was done last.
class BrowserTab {
  const BrowserTab({
    required this.page,
    required this.state,
    this.title,
    this.site,
    this.last,
  });

  /// The tab, or null when [json] is not one.
  static BrowserTab? fromJson(Object? json) {
    if (json is! Map) return null;
    final page = _address(json['page']);
    final state = json['state'];
    if (page == null || state is! String) return null;
    return BrowserTab(
      page: page,
      state: state,
      title: textOrNull(json['title']),
      site: textOrNull(json['site']),
      last: textOrNull(json['last']),
    );
  }

  final Uri page;
  final String state;
  final String? title;
  final String? site;
  final String? last;

  /// Whether the agent is using it.
  bool get working => state == 'working';

  /// Whether the user has the browser, so the agent's actions are refused.
  bool get yours => state == 'user';

  /// Whether the tab is closed.
  bool get closed => state == 'closed';

  /// What [state] says, in a sentence.
  String get says => browserStateText(state);
}

/// A request for a login, as the server reports it: its [card], the [page] with the form that
/// saves it, and [state] (`waiting`, `saving`, `saved`, `declined` or `expired`).
class BrowserLogin {
  const BrowserLogin({
    required this.card,
    required this.page,
    required this.state,
  });

  static BrowserLogin? fromJson(Object? json) {
    if (json is! Map) return null;
    final card = _address(json['card']);
    final page = _address(json['page']);
    final state = json['state'];
    if (card == null || page == null || state is! String) return null;
    return BrowserLogin(card: card, page: page, state: state);
  }

  final Uri card;
  final Uri page;
  final String state;

  /// Whether the agent is waiting for the person to enter it.
  bool get waiting => state == 'waiting';
}

/// What the server says of a chat's browser: its [tab], if it has one, and its [logins]
/// requested, newest first.
class ChatBrowser {
  const ChatBrowser({this.tab, this.logins = const []});

  /// The reply, or null when [json] is not one: an object with a `tab` or `logins`.
  static ChatBrowser? fromJson(Object? json) {
    if (json is! Map ||
        !(json.containsKey('tab') || json.containsKey('logins'))) {
      return null;
    }
    final logins = json['logins'];
    return ChatBrowser(
      tab: BrowserTab.fromJson(json['tab']),
      logins: [
        if (logins is List)
          for (final login in logins) ?BrowserLogin.fromJson(login),
      ],
    );
  }

  final BrowserTab? tab;
  final List<BrowserLogin> logins;

  /// The newest login request that is still waiting for the person.
  BrowserLogin? get waitingLogin => logins.where((l) => l.waiting).firstOrNull;
}

/// The browser's route for a chat on the [server]'s host, `/_live/browser/chat/WORKSPACE/
/// THREAD`, with [tail] after it, as `/card.jpg` or `/give`, and [query].
Uri browserRoute(
  Uri server,
  String slug,
  String thread, [
  String tail = '',
  Map<String, String>? query,
]) => liveRoute(
  server,
  'browser/chat/${Uri.encodeComponent(slug)}/${Uri.encodeComponent(thread)}$tail',
  query,
);

/// A tab's [state] in a sentence.
String browserStateText(String state) => switch (state) {
  'working' => 'The agent is using it.',
  'idle' => 'The agent has it but is not using it now.',
  'waiting' => 'The agent is waiting for you.',
  'user' => 'You have the browser.',
  'closed' => 'The browser is closed.',
  _ => 'The browser is $state.',
};

Uri? _address(Object? value) => switch (value) {
  final String text when text.isNotEmpty => Uri.tryParse(text),
  _ => null,
};

/// The browser's cards in the Markdown [markdown], in order: each linked image on the
/// [server]'s host that is a tab's card, `/_live/browser/bw-<id>.jpg` linking to
/// `/_live/browser/bw-<id>`, or a login request's, `/_live/browser/login/lr-<id>.png` linking
/// to `/_live/browser/login/lr-<id>`.
List<BrowserCard> browserCards(String markdown, {required Uri? server}) {
  if (server == null || !markdown.contains('/_live/browser/')) return const [];
  return [
    for (final (:image, :alt, :link) in linkedImagesIn(markdown))
      if (_id(image, server, _card) case final tab?
          when _id(link, server, _page) == tab)
        BrowserCard(image: image, page: link, title: alt)
      else if (_id(image, server, _loginCard) case final request?
          when _id(link, server, _loginPage) == request)
        BrowserCard(image: image, page: link, title: alt, login: true),
  ];
}

/// Whether [href] is a tab card's page on the [server]'s host, which opens the tab's take-over
/// view. A login request's page is not one: it opens its form.
bool isBrowserPage(String href, Uri? server) {
  final uri = Uri.tryParse(href);
  return uri != null && server != null && _id(uri, server, _page) != null;
}

final _card = RegExp(r'^/_live/browser/(bw-[0-9a-f]{16})\.jpg$');
final _page = RegExp(r'^/_live/browser/(bw-[0-9a-f]{16})/?$');
final _loginCard = RegExp(r'^/_live/browser/login/(lr-[0-9a-f]{32})\.png$');
final _loginPage = RegExp(r'^/_live/browser/login/(lr-[0-9a-f]{32})/?$');

/// The tab or request whose card or page ([pattern]) [uri] is, on the [server]'s host, or
/// null.
String? _id(Uri uri, Uri server, RegExp pattern) =>
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
    'browse' => switch (Uri.tryParse(text('url') ?? '')) {
      final Uri uri when uri.host.isNotEmpty => 'Opening ${_pageName(uri)}',
      _ => 'Opening a page',
    },
    'browser-act' => _acts[text('action')] ?? 'Using the browser',
    'browser-read' when args['card'] == true || args['card'] == 'true' =>
      'Getting the browser\'s card',
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

/// The page [uri] names, as its host and path without a trailing `/`, the path cut to
/// [_pathMax] characters. Never its query or fragment, which can carry a token.
String _pageName(Uri uri) {
  var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  if (path.length > _pathMax) path = '${path.substring(0, _pathMax)}…';
  return '${uri.host}$path';
}

const _pathMax = 40;

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
