import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/shortcuts.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/widgets/sheet.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// The editor's fields, in order: Name, Typed as, Prompt.
Finder _field(int n) => find
    .descendant(of: find.byType(SheetFrame), matching: find.byType(TextField))
    .at(n);

void main() {
  // Settings builds the page const, so a page that read the workspace once, outside what it
  // listens to, kept the first one: a shortcut for "this workspace only" went to it.
  testWidgets('the Shortcuts page follows a workspace opened after it shows', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer());
    expect(h.chat.activeSlug, 'q3');
    h.shell.openSettings(SettingsPage.shortcuts);
    await tester.pumpAndSettle();

    // The editor is open when another workspace opens, as from the sidebar beside Settings.
    await tester.tap(control('New shortcut'));
    await tester.pumpAndSettle();
    expect(find.text('Only Q3 planning'), findsOneWidget);
    await h.chat.select('household');
    await tester.pumpAndSettle();
    expect(find.text('Only Household'), findsOneWidget);
    expect(find.text('Only Q3 planning'), findsNothing);

    await tester.enterText(_field(0), 'Formal');
    await tester.enterText(_field(1), 'formal');
    await tester.enterText(_field(2), 'Rewrite it formally.');
    await tester.pumpAndSettle();
    await tapVisible(tester, control('Only Household'));
    await tester.pumpAndSettle();
    await tapVisible(tester, control('Save'));
    await tester.pumpAndSettle();

    final saved = h.prefs.prefs.shortcuts.single;
    expect(
      saved.workspaceKey,
      Prefs.offKey(h.chat.server!.baseUrl, 'household'),
    );
  });

  // Selecting a workspace also writes the prefs, which the page listened to already; this
  // keeps the count honest should that ever change.
  testWidgets('the Chat page counts the open workspace\'s shortcuts', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer());
    final server = h.chat.server!.baseUrl;
    await h.prefs.saveShortcut(
      PromptShortcut(
        id: '1',
        name: 'formal',
        label: 'Formal',
        prompt: 'Rewrite it formally.',
        workspaceKey: Prefs.offKey(server, 'household'),
      ),
    );
    h.shell.openSettings(SettingsPage.chat);
    await tester.pumpAndSettle();
    final built = builtInPromptShortcuts.length;
    expect(find.text('$built prompts · type / to use them'), findsOneWidget);

    await h.chat.select('household');
    await tester.pumpAndSettle();
    expect(
      find.text('${built + 1} prompts · type / to use them'),
      findsOneWidget,
    );
  });

  testWidgets('Save checks the fields and says under each what is wrong', (
    tester,
  ) async {
    final h = await pumpApp(tester, llm: planningServer());
    h.shell.openSettings(SettingsPage.shortcuts);
    await tester.pumpAndSettle();
    await tester.tap(control('New shortcut'));
    await tester.pumpAndSettle();
    // Nothing is said before Save but the rules.
    expect(find.text('Give it a name.'), findsNothing);
    final save = tester.widget<Tappable>(control('Save'));
    expect(save.onTap, isNotNull);

    await tapVisible(tester, control('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Give it a name.'), findsOneWidget);
    expect(find.text('Choose what you type after /.'), findsOneWidget);
    expect(find.text('Write the prompt it sends.'), findsOneWidget);
    expect(h.prefs.prefs.shortcuts, isEmpty);

    // Each goes as its field is put right.
    await tester.enterText(_field(0), 'Formal');
    await tester.enterText(_field(1), 'summarise');
    await tester.pumpAndSettle();
    expect(find.text('Give it a name.'), findsNothing);
    expect(
      find.text('Another shortcut already uses that name.'),
      findsOneWidget,
    );
    await tester.enterText(_field(1), 'formal');
    await tester.enterText(_field(2), 'Rewrite it formally.');
    await tester.pumpAndSettle();
    await tapVisible(tester, control('Save'));
    await tester.pumpAndSettle();
    expect(h.prefs.prefs.shortcuts.single.name, 'formal');
    expect(find.byType(SheetFrame), findsNothing);
  });

  testWidgets(
    'Delete shortcut acts at once, and Undo puts it back in its place',
    (tester) async {
      final h = await pumpApp(tester, llm: planningServer());
      for (final (id, name) in [('1', 'formal'), ('2', 'casual')]) {
        await h.prefs.saveShortcut(
          PromptShortcut(
            id: id,
            name: name,
            label: name,
            prompt: 'Say it $name.',
          ),
        );
      }
      h.shell.openSettings(SettingsPage.shortcuts);
      await tester.pumpAndSettle();
      await tapVisible(tester, control('formal, /formal, Edit'));
      await tester.pumpAndSettle();
      await tapVisible(tester, control('Delete shortcut'));
      await tester.pumpAndSettle();
      expect(find.byType(SheetFrame), findsNothing);
      expect(find.text('Delete formal?'), findsNothing);
      expect(h.prefs.prefs.shortcuts.map((s) => s.id), ['2']);
      expect(find.text('Deleted formal'), findsOneWidget);
      // No timer.
      await tester.pump(const Duration(minutes: 1));
      expect(find.text('Deleted formal'), findsOneWidget);

      await tester.tap(control('Undo'));
      await tester.pumpAndSettle();
      expect(h.prefs.prefs.shortcuts.map((s) => s.id), ['1', '2']);
      expect(find.text('Deleted formal'), findsNothing);

      // Close lets it go for good.
      await tapVisible(tester, control('formal, /formal, Edit'));
      await tester.pumpAndSettle();
      await tapVisible(tester, control('Delete shortcut'));
      await tester.pumpAndSettle();
      await tester.tap(control('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Deleted formal'), findsNothing);
      expect(h.prefs.prefs.shortcuts.map((s) => s.id), ['2']);
    },
  );
}
