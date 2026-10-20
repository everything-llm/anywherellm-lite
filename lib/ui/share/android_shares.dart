import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/files.dart';
import 'shared_item.dart';

/// `MainActivity`'s share intake (`Shares.kt`).
const _channel = MethodChannel('anywherellm/shares');

/// What other apps share with AnywhereLLM on Android: what started the app, then each share
/// that reaches it while it runs. A file is read only when it is used, from the address the
/// sharing app gave, and never written to a file.
Stream<SharedItem> androidShares() {
  late final StreamController<SharedItem> items;
  void take(Object? share) {
    if (_itemOf(share) case final item?) items.add(item);
  }

  items = StreamController(
    onListen: () async {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'share') take(call.arguments);
      });
      try {
        take(await _channel.invokeMethod<Object?>('launchShare'));
      } on MissingPluginException {
        // The app runs without `MainActivity`'s channel, as in a test.
      }
    },
    onCancel: () => _channel.setMethodCallHandler(null),
  );
  return items.stream;
}

/// The item [share] holds, as the activity hands it over: `{text}`, or `{file, name, size}`
/// where `file` is the id it is read by; null for none.
SharedItem? _itemOf(Object? share) => switch (share) {
  {'text': final String text} => sharedTextItem(text),
  {'file': final int id, 'size': final int size} => SharedFile(
    // The name is the sharing app's to choose, so it is made one that names no other folder.
    plainFileName(share['name'] as String? ?? '', fallback: 'shared file'),
    size,
    () async => (await _channel.invokeMethod<Uint8List>('read', {'id': id}))!,
  ),
  _ => null,
};
