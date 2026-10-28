import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/shortcuts.dart';
import 'package:anywherellm/ui/settings/settings_pages.dart';
import 'package:anywherellm/ui/widgets/sheet.dart';
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
}
