import 'package:flutter/widgets.dart';

import '../core/chat.dart';
import 'app_scope.dart';

/// Opens [href], a link in an answer, outside the app. Only web and mail links open; anything
/// else, or a link nothing on the device opens, becomes a notice in the chat.
Future<void> openLink(BuildContext context, String href) async {
  final scope = AppScope.of(context);
  final url = openableLink(href);
  if (url == null) {
    scope.chat.report(
      'Could not open the link',
      'AnywhereLLM opens only web and mail links, not $href',
    );
    return;
  }
  var opened = false;
  try {
    opened = await scope.openLink(url);
  } on Exception {
    opened = false;
  }
  if (!opened) {
    scope.chat.report(
      'Could not open the link',
      'Nothing on this device opened $url',
    );
  }
}
