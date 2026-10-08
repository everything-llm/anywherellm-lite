import 'package:share_plus/share_plus.dart' show XFile;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'shared_item.dart';

/// What other apps share with AnywhereLLM on Android: what started the app, then each share
/// that reaches it while it runs. A file is read only when it is used.
Stream<SharedItem> androidShares() async* {
  final intent = ReceiveSharingIntent.instance;
  final first = await intent.getInitialMedia();
  await intent.reset();
  for (final media in first) {
    yield await _itemOf(media);
  }
  await for (final batch in intent.getMediaStream()) {
    for (final media in batch) {
      yield await _itemOf(media);
    }
  }
}

Future<SharedItem> _itemOf(SharedMediaFile media) async {
  switch (media.type) {
    case SharedMediaType.text || SharedMediaType.url:
      return sharedTextItem(media.path);
    case SharedMediaType.image || SharedMediaType.video || SharedMediaType.file:
      final file = XFile(media.path);
      final name = media.path.split('/').last;
      return SharedFile(name, await file.length(), file.readAsBytes);
  }
}
