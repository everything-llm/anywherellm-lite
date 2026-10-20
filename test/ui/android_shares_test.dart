import 'package:anywherellm/ui/share/android_shares.dart';
import 'package:anywherellm/ui/share/shared_item.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('anywherellm/shares');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// The calls the app made to the activity, answered by [launch] and [files] by id.
  late List<MethodCall> calls;

  void activity({Object? launch, Map<int, List<int>> files = const {}}) {
    calls = [];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'launchShare' => launch,
        'read' => Uint8List.fromList(files[(call.arguments as Map)['id']]!),
        _ => null,
      };
    });
  }

  /// The activity handing over a share that reached the app while it runs.
  Future<void> shareWhileRunning(Object share) =>
      messenger.handlePlatformMessage(
        _channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('share', share),
        ),
        (_) {},
      );

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test(
    'a shared file keeps a name that stays in its folder, read only when used',
    () async {
      activity(
        launch: {'file': 7, 'name': '../files/prefs.json', 'size': 4},
        files: {
          7: [1, 2, 3, 4],
        },
      );
      final file = await androidShares().first as SharedFile;
      expect(file.name, '..-files-prefs.json');
      expect(file.size, 4);
      expect(calls.map((c) => c.method), ['launchShare']);
      expect(await file.read(), [1, 2, 3, 4]);
      expect(calls.last.arguments, {'id': 7});
    },
  );

  test('a share while the app runs follows the one that started it', () async {
    activity(launch: {'text': 'Service due every 12 months.'});
    final items = <SharedItem>[];
    final listening = androidShares().listen(items.add);
    await pumpEventQueue();
    await shareWhileRunning({
      'text': 'anywherellm://connect?url=https://h.example&key=K',
    });
    await pumpEventQueue();
    await listening.cancel();
    expect(items, [isA<SharedText>(), isA<SharedPairing>()]);
  });

  test('nothing started the app, so nothing is shared', () async {
    activity();
    final items = <SharedItem>[];
    final listening = androidShares().listen(items.add);
    await pumpEventQueue();
    await listening.cancel();
    expect(items, isEmpty);
  });
}
