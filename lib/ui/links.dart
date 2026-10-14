import 'package:flutter/widgets.dart';

import '../core/apps.dart';
import '../core/browser.dart';
import '../core/chat.dart';
import 'app_scope.dart';

/// Opens [href], a link in an answer, outside the app. Only web and mail links open; anything
/// else, or a link nothing on the device opens, becomes a short notice in the chat.
Future<void> openLink(BuildContext context, String href) async {
  final scope = AppScope.of(context);
  final url = openableLink(href, server: scope.settings.connection?.uri);
  if (url == null) {
    final scheme = Uri.tryParse(href.trim())?.scheme ?? '';
    scope.chat.reportLink(
      'Could not open the link',
      scheme.isEmpty || scheme.length > 20
          ? 'AnywhereLLM opens only web and mail links, not this link.'
          : 'AnywhereLLM opens only web and mail links, not $scheme: links.',
    );
    return;
  }
  var opened = false;
  try {
    opened = await scope.launch(url);
  } on Object {
    opened = false;
  }
  if (!opened) {
    scope.chat.reportLink(
      'Could not open the link',
      'Nothing on this device opened ${url.scheme == 'mailto' ? 'the mail link' : url.host}.',
    );
  }
}

/// Opens [href], a link in an answer: an app's page or card opens the app full screen where
/// the apps server is there, browser-lean's page for an agent's tab opens in its sheet where
/// the device has a web view ([browserTabOf]), and anything else as [openLink] does.
Future<void> openAnswerLink(BuildContext context, String href) async {
  final scope = AppScope.of(context);
  final server = scope.settings.connection?.uri;
  final parsed = Uri.tryParse(href.trim());
  final url = parsed == null ? null : onServer(parsed, server);
  final app = url == null || scope.apps.available != true
      ? null
      : appRefOf(url, cards: scope.apps.cards, pages: scope.apps.pages);
  if (app != null) return scope.shell.openApp(app);
  if (url != null && scope.appView != null) {
    if (browserTabOf(url, server) case final tab?) {
      return scope.shell.openBrowser(tab);
    }
  }
  await openLink(context, href);
}

/// Opens AnythingLLM's own web page, at the connected server's address.
Future<void> openServerPage(BuildContext context) async {
  if (AppScope.of(context).settings.connection case final connection?) {
    await openLink(context, connection.uri.toString());
  }
}
