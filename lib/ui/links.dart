import 'package:flutter/material.dart';

import '../core/chat.dart';
import '../core/skill_pages.dart';
import 'app_scope.dart';

/// Opens [link] outside the app. Only web and mail links open; anything else, or a link nothing
/// on the device opens, becomes a short notice in the chat.
Future<void> openLink(BuildContext context, Uri link) async {
  final scope = AppScope.of(context);
  final url = openableLink(link, server: scope.settings.connection?.uri);
  if (url == null) return _refused(scope, link.scheme);
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

/// Says in the chat that a link of [scheme] does not open, naming the scheme when it reads as
/// one.
void _refused(AppScope scope, String scheme) => scope.chat.reportLink(
  'Could not open the link',
  scheme.isEmpty || scheme.length > 20
      ? 'AnywhereLLM opens only web and mail links, not this link.'
      : 'AnywhereLLM opens only web and mail links, not $scheme: links.',
);

/// Opens [href], a link in an answer as written: one of the suite's pages ([skillLinkOf]) opens
/// as [openSkillPage] opens it, and anything else as [openLink] does.
Future<void> openAnswerLink(BuildContext context, String href) async {
  final scope = AppScope.of(context);
  final server = scope.settings.connection?.uri;
  if (skillLinkOf(href, server) case (final page, final url)) {
    return openSkillPage(context, page, url);
  }
  final link = Uri.tryParse(href.trim());
  if (link == null) return _refused(scope, '');
  await openLink(context, onServer(link, server));
}

/// Opens [url], the suite's [page] on the connected server, where the device has a web view:
/// browser-lean's page for an agent's tab in its sheet, and any other in the page's sheet at
/// [SkillPage.openedAt], in the theme the app shows in and on the open workspace. Without a web
/// view it opens as [openLink] does.
Future<void> openSkillPage(
  BuildContext context,
  SkillPage page,
  Uri url,
) async {
  final scope = AppScope.of(context);
  if (scope.appView == null) return openLink(context, url);
  if (page == SkillPage.browserTab) return scope.shell.openBrowser(url);
  scope.shell.openPage(
    page.openedAt(
      url,
      dark: Theme.of(context).brightness == Brightness.dark,
      workspace: scope.chat.activeSlug,
    ),
  );
}

/// Opens AnythingLLM's own web page, at the connected server's address.
Future<void> openServerPage(BuildContext context) async {
  if (AppScope.of(context).settings.connection case final connection?) {
    await openLink(context, connection.uri);
  }
}
