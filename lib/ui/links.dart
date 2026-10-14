import 'package:flutter/widgets.dart';

import '../core/apps_lean.dart';
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

/// Opens [href], a link in an answer: where the device has a web view, browser-lean's page for
/// an agent's tab opens in its sheet ([isBrowserTab]) and an apps-lean app's page in the page's
/// sheet ([isAppsLeanPage]); anything else opens as [openLink] does.
Future<void> openAnswerLink(BuildContext context, String href) async {
  final scope = AppScope.of(context);
  final server = scope.settings.connection?.uri;
  final url = openableLink(href, server: server);
  if (url != null && scope.appView != null) {
    if (isBrowserTab(url, server)) return scope.shell.openBrowser(url);
    if (isAppsLeanPage(url, server)) return scope.shell.openPage(url);
  }
  await openLink(context, url?.toString() ?? href);
}

/// Opens AnythingLLM's own web page, at the connected server's address.
Future<void> openServerPage(BuildContext context) async {
  if (AppScope.of(context).settings.connection case final connection?) {
    await openLink(context, connection.uri.toString());
  }
}
