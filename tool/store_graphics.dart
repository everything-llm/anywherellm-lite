// The F-Droid store page's pictures: the feature graphic and the phone screenshots, drawn by the
// app itself over the test fakes, so no real server or data is shown.
//
//   flutter test tool/store_graphics.dart
//
// writes them, laid out as fastlane's `en-US/`, to `$STORE_GRAPHICS` or else `build/store/en-US`.
// It sits outside `test/`, so the suite does not run it.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/type.dart';
import 'package:anywherellm/ui/widgets/robin_mark.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/fake_api.dart';
import '../test/support/fake_settings.dart';
import '../test/support/pump.dart';

/// A phone's screen in logical pixels, and the density its screenshots are drawn at.
const _phone = Size(412, 892);
const _density = 2.625;

final _out = Directory(
  Platform.environment['STORE_GRAPHICS'] ?? 'build/store/en-US',
);

/// Loads the app's own faces, which a test otherwise draws as boxes.
Future<void> _loadFonts() async {
  const fonts = {
    'Instrument Sans': ['InstrumentSans.ttf'],
    'JetBrains Mono': ['JetBrainsMono.ttf'],
  };
  for (final MapEntry(key: family, value: files) in fonts.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(
        File('assets/fonts/$file')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)),
      );
    }
    await loader.load();
  }
}

/// Writes what the window shows to [name], drawn at [density].
Future<void> _capture(
  WidgetTester tester,
  String name, {
  double density = _density,
}) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(
      Offset.zero & view.size,
      pixelRatio: density,
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('${_out.path}/$name')..parent.createSync(recursive: true);
    file.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// A server with a few workspaces and a budget chat worth looking at.
FakeAnythingLlm _server() {
  final llm = FakeAnythingLlm()..relay = true;
  llm.spaces = [
    FakeWorkspace(
      'q3',
      'Q3 planning',
      threads: const [
        Thread(slug: 'hiring', name: 'Hiring plan'),
        Thread(slug: 'priorities', name: 'Quarter priorities'),
        Thread(slug: 'budget', name: 'Budget questions'),
      ],
      docs: [
        libraryDoc(llm, 'Q3 roadmap.pdf'),
        libraryDoc(llm, 'Budget forecast.xlsx'),
        libraryDoc(llm, 'Customer interviews.docx'),
        libraryDoc(llm, 'Vendor quote.pdf'),
      ],
    ),
    FakeWorkspace(
      'household',
      'Household',
      threads: const [Thread(slug: 'boiler', name: 'When is the boiler due?')],
    ),
    FakeWorkspace(
      'reading',
      'Reading notes',
      threads: const [Thread(slug: 'essays', name: 'Themes across the essays')],
    ),
    FakeWorkspace('lisbon', 'Trip to Lisbon'),
  ];
  llm.histories['budget'] = const [
    ChatMessage(role: Role.user, text: 'How is the Q3 budget split?'),
    ChatMessage(
      role: Role.assistant,
      text:
          'The Q3 budget is **about 42k**, split across three areas:\n\n'
          '- **Hiring**: 24k for two contract designers\n'
          '- **Tooling**: 11k, mostly the analytics renewal\n'
          '- **Events**: 7k for the customer summit\n\n'
          'The roadmap flags the analytics renewal as the item most likely to '
          'move, since the vendor\'s new quote is due in August.',
      citations: [
        Citation('Budget forecast.xlsx'),
        Citation('Q3 roadmap.pdf'),
        Citation('Vendor quote.pdf'),
      ],
    ),
    ChatMessage(role: Role.user, text: 'What would a 10% cut drop first?'),
    ChatMessage(
      role: Role.assistant,
      text:
          'A 4.2k cut would most likely come out of **Events**: the forecast '
          'marks the summit\'s venue upgrade (3.5k) as optional, and the '
          'customer interviews rank the summit below the analytics work.',
      citations: [
        Citation('Budget forecast.xlsx'),
        Citation('Customer interviews.docx'),
      ],
    ),
  ];
  return llm;
}

/// The banner across the top of the store page: the robin and the name on the icon's ground.
class _FeatureGraphic extends StatelessWidget {
  const _FeatureGraphic();

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: iconGround,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RobinMark(size: 300, color: iconInk),
            const SizedBox(width: 16),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AnywhereLLM',
                  style: Type.sans(
                    104,
                    weight: FontWeight.w700,
                    color: iconInk,
                    height: 1,
                    letterSpacing: -2,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Your AnythingLLM server,\nin your pocket',
                  style: Type.sans(
                    30,
                    weight: FontWeight.w500,
                    color: iconInk.withValues(alpha: 0.8),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('the feature graphic', (tester) async {
    tester.view.physicalSize = const Size(1024, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const _FeatureGraphic());
    await _capture(tester, 'featureGraphic.png', density: 1);
  });

  testWidgets('the phone screenshots', (tester) async {
    final h = await pumpApp(
      tester,
      llm: _server(),
      size: _phone,
      sourcesOpen: false,
      connection: const Connection(
        baseUrl: 'https://anythingllm.example.ts.net',
        apiKey: 'K1',
      ),
      // A pinned chat, so the sidebar shows its groups: Pinned, Recent and All chats.
      prefsStore: FakePrefsStore(
        Prefs(
          theme: ThemePref.dark,
          pinned: {
            Prefs.offKey('https://anythingllm.example.ts.net', 'q3'): const [
              'priorities',
            ],
          },
          recent: {
            Prefs.offKey('https://anythingllm.example.ts.net', 'q3'): const [
              'budget',
              'hiring',
            ],
          },
        ),
      ),
    );
    await _capture(tester, 'phoneScreenshots/1_chat.png');

    // The sidebar with the workspace's chats, then its workspace menu open over them.
    h.shell.toggleSide();
    await tester.pumpAndSettle();
    await _capture(tester, 'phoneScreenshots/2_chats.png');
    h.shell.togglePopup(Popup.workspaces);
    await tester.pumpAndSettle();
    await _capture(tester, 'phoneScreenshots/3_workspaces.png');

    h.shell.closeSide();
    h.shell.openSources();
    await tester.pumpAndSettle();
    await _capture(tester, 'phoneScreenshots/4_sources.png');

    h.shell.closeSources();
    h.shell.openSettings();
    await tester.pumpAndSettle();
    await _capture(tester, 'phoneScreenshots/5_settings.png');

    h.shell.showSettingsPage(SettingsPage.connection);
    await tester.pumpAndSettle();
    await _capture(tester, 'phoneScreenshots/6_connection.png');
  });
}
