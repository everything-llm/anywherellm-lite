import 'package:anywherellm/ui/chat/composer.dart';
import 'package:anywherellm/core/files.dart';
import 'package:anywherellm/ui/files/workspace_pages.dart';
import 'package:anywherellm/ui/settings/settings_dialog.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/sources/sources_panel.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/workspace_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// A phone in portrait, and the on-screen keyboard's height on it.
const phone = Size(360, 640);
const keyboard = 300.0;

/// A phone on its side, and the keyboard's height on it: 160 of its 360 pixels are left.
const side = Size(640, 360);
const sideKeyboard = 200.0;

/// The composer's text field.
Finder get composerField => typingField(find.byType(Composer));

/// Expects what [finder] finds to lie wholly in the part of [screen] a keyboard [height]
/// pixels tall leaves.
void expectAboveKeyboard(
  WidgetTester tester,
  Finder finder,
  Size screen,
  double height,
) {
  final rect = tester.getRect(finder);
  expect(rect.bottom, lessThanOrEqualTo(screen.height - height));
  expect(rect.top, greaterThanOrEqualTo(0));
}

void main() {
  testWidgets('the composer sits above the keyboard', (tester) async {
    await pumpApp(tester, llm: planningServer(), size: phone);
    await tester.tap(composerField);
    raiseKeyboard(tester, keyboard);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(focused(tester, composerField), isTrue);
    expectAboveKeyboard(tester, find.byType(Composer), phone, keyboard);
  });

  testWidgets('a Settings field in use sits above the keyboard', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: planningServer(),
      size: phone,
      connection: null,
    );
    h.shell.openSettings(SettingsPage.connection);
    await tester.pumpAndSettle();
    final key = typingField(find.byType(SettingsDialog)).last;
    await tapVisible(tester, key);
    raiseKeyboard(tester, keyboard);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(focused(tester, key), isTrue);
    expectAboveKeyboard(tester, key, phone, keyboard);
  });

  testWidgets('Connect stays above the keyboard on the first run', (
    tester,
  ) async {
    final h = await pumpApp(
      tester,
      llm: planningServer(),
      size: phone,
      connection: null,
    );
    h.shell.openSettings(SettingsPage.connection);
    await tester.pumpAndSettle();
    expect(control('How connecting works'), findsOneWidget);
    final field = typingField(find.byType(SettingsDialog)).first;
    await tester.tap(field);
    raiseKeyboard(tester, keyboard);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(focused(tester, field), isTrue);
    expectAboveKeyboard(tester, control('Connect'), phone, keyboard);
    expectAboveKeyboard(tester, field, phone, keyboard);
    // The page scrolls to its fields, so the key's field is in view too.
    expectAboveKeyboard(
      tester,
      typingField(find.byType(SettingsDialog)).last,
      phone,
      keyboard,
    );
    // The page is all fields now: the help link waits for the keyboard to go.
    expect(control('How connecting works'), findsNothing);
  });

  testWidgets('a phone on its side keeps the composer above the keyboard', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer(), size: side);
    await tester.tap(composerField);
    raiseKeyboard(tester, sideKeyboard);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectAboveKeyboard(tester, composerField, side, sideKeyboard);
  });

  testWidgets(
    'a Sources field in use on a phone on its side is above the keyboard',
    (tester) async {
      final h = await pumpApp(tester, llm: planningServer(), size: side);
      h.shell.openSources();
      await tester.pumpAndSettle();
      final add = find.bySemanticsLabel('Add a link').last;
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      final field = typingField(find.byType(SourcesPanel)).first;
      await tester.tap(field, warnIfMissed: false);
      raiseKeyboard(tester, sideKeyboard);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(focused(tester, field), isTrue);
      expectAboveKeyboard(tester, field, side, sideKeyboard);
    },
  );

  testWidgets('the shelf on a phone on its side scrolls above the keyboard', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer(), size: side, shelf: true);
    raiseKeyboard(tester, sideKeyboard);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'New workspace on a phone on its side keeps its fields above the keyboard',
    (tester) async {
      final h = await pumpApp(tester, llm: planningServer(), size: side);
      h.shell.togglePopup(WorkspaceSheet.create);
      await tester.pumpAndSettle();
      final sheet = find.byType(WorkspaceSheetView);
      final name = typingField(sheet).first;
      await tester.tap(name, warnIfMissed: false);
      raiseKeyboard(tester, sideKeyboard);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(focused(tester, name), isTrue);
      expectAboveKeyboard(tester, name, side, sideKeyboard);
      final instructions = typingField(sheet).last;
      await tester.ensureVisible(instructions);
      // Only its top shows in the 160 pixels left, so it is tapped there.
      await tester.tapAt(
        tester.getRect(instructions).topCenter.translate(0, 12),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(focused(tester, instructions), isTrue);
      expect(
        tester.getRect(instructions).top,
        lessThan(side.height - sideKeyboard),
      );
    },
  );

  testWidgets(
    'a workspace prompt being edited on a phone on its side is above the keyboard',
    (tester) async {
      final h = await pumpApp(tester, llm: planningServer(), size: side);
      h.shell
        ..showPane(Pane.files)
        ..showWorkspacePage(FilesSection.instructions);
      await tester.pumpAndSettle();
      await h.files.openSection(FilesSection.instructions);
      await tester.pumpAndSettle();
      final field = typingField(find.byType(WorkspacePages)).first;
      await tester.tap(field, warnIfMissed: false);
      raiseKeyboard(tester, sideKeyboard);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(focused(tester, field), isTrue);
      // The prompt is taller than what the keyboard leaves, so only its top need show.
      expect(tester.getRect(field).top, lessThan(side.height - sideKeyboard));
    },
  );

  testWidgets('with the keyboard down, the composer is at the bottom', (
    tester,
  ) async {
    await pumpApp(tester, llm: planningServer(), size: phone);
    expect(
      tester.getRect(find.byType(Composer)).bottom,
      greaterThan(phone.height - keyboard),
    );
  });
}
