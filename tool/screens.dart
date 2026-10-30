// Each screen of the app drawn at a phone's size, 390 by 844 logical pixels at one pixel each,
// in the light and the dark theme, over the test fakes holding the design prototype's sample
// data, to be laid beside the prototype's own pictures:
//
//   flutter test tool/screens.dart
//
// and the wide window's screens at 1440 by 900 (`desk-*`), and writes `<screen>-light.png` and `<screen>-dark.png` to `$SCREENS` or else `build/screens`.
// `flutter test tool/screens.dart --plain-name chats` draws one screen. It sits outside `test/`,
// so the suite does not run it.

import 'dart:io';

import 'package:anywherellm/ui/chat/answer_menu.dart';
import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/server_models.dart';
import 'package:anywherellm/core/files.dart';
import 'package:anywherellm/ui/chat/message_list.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/settings/walkthrough.dart';
import 'package:anywherellm/ui/share/shared_item.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/fake_settings.dart';
import '../test/support/pump.dart';
import 'sample.dart';
import 'support.dart';

final _out = Directory(Platform.environment['SCREENS'] ?? 'build/screens');

/// A step that brings a screen up once the app shows its chat.
typedef _Setup = Future<void> Function(WidgetTester tester, Harness h);

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _openChat(WidgetTester tester, Harness h, String thread) async {
  final slug = h.llm.spaces
      .firstWhere((w) => w.threads.any((t) => t.slug == thread))
      .slug;
  h.shell.openChat();
  await h.chat.select(slug, thread: thread);
  await _settle(tester);
}

Future<void> _workspace(WidgetTester tester, Harness h) async {
  h.shell.showPane(Pane.files);
  await _settle(tester);
}

Future<void> _section(
  WidgetTester tester,
  Harness h,
  FilesSection section,
) async {
  await _workspace(tester, h);
  h.shell.showWorkspacePage(section);
  h.files.openSection(section);
  await _settle(tester);
}

Future<void> _settings(
  WidgetTester tester,
  Harness h,
  SettingsPage page,
) async {
  h.shell
    ..openSettings()
    ..showSettingsPage(page);
  await _settle(tester);
}

Thread _thread(Harness h, String slug) =>
    h.llm.spaces.expand((w) => w.threads).firstWhere((t) => t.slug == slug);

final _screens = <String, _Setup>{
  'chats': (tester, h) async {},
  'chat': (tester, h) => _openChat(tester, h, 'errands'),
  'hero': (tester, h) async {
    h.chat.newChat();
    h.shell.openChat();
    await _settle(tester);
  },
  'streamed': (tester, h) async {
    h.chat.newChat();
    h.shell.openChat();
    await _settle(tester);
    await h.chat.send('Summarise Boiler manual');
    await _settle(tester);
  },
  'budget': (tester, h) => _openChat(tester, h, 'budget'),
  'research': (tester, h) => _openChat(tester, h, 'research'),
  // Scrolled up from the newest text, with the button that jumps back to it.
  'scrolled': (tester, h) async {
    final once = h.llm.histories['research']!;
    h.llm.histories['research'] = [...once, ...once, ...once];
    await _openChat(tester, h, 'research');
    await tester.drag(find.byType(MessageList), const Offset(0, 300));
    await _settle(tester);
  },
  'settings': (tester, h) async {
    h.shell.openSettings();
    await _settle(tester);
  },
  'conn': (tester, h) => _settings(tester, h, SettingsPage.connection),
  'appear': (tester, h) => _settings(tester, h, SettingsPage.appearance),
  'chatset': (tester, h) => _settings(tester, h, SettingsPage.chat),
  'server': (tester, h) => _settings(tester, h, SettingsPage.server),
  'privacy': (tester, h) => _settings(tester, h, SettingsPage.privacy),
  'workspace': _workspace,
  'docs': (tester, h) async {
    await _workspace(tester, h);
    h.shell.openSources();
    await _settle(tester);
  },
  'docremove': (tester, h) async {
    await _workspace(tester, h);
    h.shell.openSources();
    await _settle(tester);
    await tester.tap(
      find.byTooltip('Remove Home insurance.pdf from workspace'),
    );
    await _settle(tester);
  },
  'instr': (tester, h) => _section(tester, h, FilesSection.instructions),
  'answers': (tester, h) => _section(tester, h, FilesSection.answers),
  'wsmenu': (tester, h) async {
    h.shell.togglePopup(Popup.workspaces);
    await _settle(tester);
  },
  'wsnew': (tester, h) async {
    h.shell.togglePopup(WorkspaceSheet.create);
    await _settle(tester);
  },
  'wsrename': (tester, h) async {
    await _workspace(tester, h);
    h.shell.togglePopup(WorkspaceSheet.rename);
    await _settle(tester);
  },
  'wsdel': (tester, h) async {
    await _workspace(tester, h);
    h.shell.togglePopup(WorkspaceSheet.delete);
    await _settle(tester);
  },
  'chatsheet': (tester, h) async {
    h.shell.openChatSheet(_thread(h, 'errands'));
    await _settle(tester);
  },
  // Delete chat acts at once, with a toast to undo it.
  'chatdel': (tester, h) async {
    await _openChat(tester, h, 'errands');
    await h.chat.delete(_thread(h, 'errands').slug);
    await _settle(tester);
  },
  'attach': (tester, h) async {
    await _openChat(tester, h, 'errands');
    h.shell.togglePopup(Popup.attach);
    await _settle(tester);
  },
  'more': (tester, h) async {
    await _openChat(tester, h, 'errands');
    h.shell.togglePopup(h.chat.turns[1]);
    await _settle(tester);
  },
  'answermenu': (tester, h) async {
    await _openChat(tester, h, 'errands');
    h.shell.togglePopup(answerSheetOf(h.chat.turns.last));
    await _settle(tester);
  },
  'answerfrom': (tester, h) async {
    await _openChat(tester, h, 'errands');
    h.shell.togglePopup(Popup.answerFrom);
    await _settle(tester);
  },
  'passages': (tester, h) async {
    await _openChat(tester, h, 'budget');
    await tester.tap(find.byTooltip('Passages read'));
    await _settle(tester);
  },
  'sources': (tester, h) async {
    await _openChat(tester, h, 'research');
    h.shell.toggleCited(h.chat.turns[1].citations);
    await _settle(tester);
  },
  'shelf': (tester, h) async {
    await _openChat(tester, h, 'errands');
    h.shell.openShelf();
    await _settle(tester);
  },
  'share': (tester, h) async {
    h.shell.showShared(
      SharedLink(
        Uri.parse('https://energy-advice.example/boilers'),
        title: 'Boiler maintenance guide',
      ),
    );
    await _settle(tester);
  },
};

/// The screens drawn with no server saved.
final _signedOut = <String, _Setup>{
  'welcome': (tester, h) async {
    h.shell.openSettings(SettingsPage.connection);
    await _settle(tester);
  },
  'scan': (tester, h) async {
    h.shell
      ..openSettings(SettingsPage.connection)
      ..setScanning(true);
    await _settle(tester);
  },
  for (var n = 0; n < connectSteps.length; n++)
    'howto${n + 1}': (tester, h) async {
      h.shell
        ..openSettings(SettingsPage.connection)
        ..showGuide(Guide.connect);
      await _settle(tester);
      for (var i = 0; i < n; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await _settle(tester);
      }
    },
};

/// The screens drawn on a desktop's window, 1440 by 900, with the chats as a sidebar.
final _wide = <String, _Setup>{
  'desk-answer': (tester, h) => _openChat(tester, h, 'budget'),
  'desk-documents': (tester, h) async {
    await _openChat(tester, h, 'budget');
    h.shell.openPane(Pane.documents);
    await _settle(tester);
  },
  'desk-settings': (tester, h) => _settings(tester, h, SettingsPage.connection),
};

/// The desktop's window.
const _desktop = Size(1440, 900);

void main() {
  setUpAll(loadFonts);

  for (final (screens, connected, size) in [
    (_screens, true, phoneSize),
    (_signedOut, false, phoneSize),
    (_wide, true, _desktop),
  ]) {
    for (final MapEntry(key: name, value: setup) in screens.entries) {
      testWidgets(name, (tester) async {
        // Tests draw shadows unblurred unless told otherwise; the pictures show them as a phone
        // does.
        debugDisableShadows = false;
        for (final theme in [ThemePref.light, ThemePref.dark]) {
          final llm = sampleServer();
          final h = await pumpApp(
            tester,
            llm: llm,
            size: size,
            shelf: size == phoneSize,
            canScan: !connected,
            canDictate: true,
            canSpeak: true,
            canPickPhotos: true,
            canShare: true,
            connection: connected ? sampleServerConnection : null,
            prefsStore: FakePrefsStore(Prefs(theme: theme)),
          );
          await _settle(tester);
          await setup(tester, h);
          await capture(tester, _out, '$name-${theme.name}.png');
          // A fresh app for the next theme.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
        debugDisableShadows = true;
      });
    }
  }
}
