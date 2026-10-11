import 'dart:async';
import 'dart:io';

import 'package:anywherellm/ui/share/share_sheet.dart';
import 'package:anywherellm/ui/share/shared_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

const phone = Size(390, 844);

/// Shares [item] with the app, as another app's share sheet does.
Future<void> share(
  WidgetTester tester,
  StreamController<SharedItem> shares,
  SharedItem item,
) async {
  shares.add(item);
  await tester.pumpAndSettle();
}

Finder inSheet(Finder finder) =>
    find.descendant(of: find.byType(ShareSheet), matching: finder);

void main() {
  test('shared text is a link when it is an address, or a title over one', () {
    expect(
      (sharedTextItem('https://example.test/a') as SharedLink).url.path,
      '/a',
    );
    final titled = sharedTextItem('Boiler prices\nhttps://example.test/p');
    expect((titled as SharedLink).title, 'Boiler prices');
    expect(sharedTextItem('Service due every 12 months.'), isA<SharedText>());
    expect(
      sharedTextItem('See https://example.test/p for prices'),
      isA<SharedText>(),
    );
  });

  testWidgets('a shared link is added to the chosen workspace\'s documents', (
    tester,
  ) async {
    final shares = StreamController<SharedItem>();
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm, size: phone, shares: shares);
    await share(
      tester,
      shares,
      SharedLink(Uri.parse('https://example.test/prices'), title: 'Prices'),
    );
    expect(inSheet(find.text('Share to AnywhereLLM')), findsOneWidget);
    expect(inSheet(find.text('Prices')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(inSheet(control('Household')));
    await tester.pumpAndSettle();
    await tester.tap(inSheet(control('Add to documents')));
    await tester.pumpAndSettle();
    expect(h.chat.activeSlug, 'household');
    expect(llm.calls, contains('uploadLink:https://example.test/prices'));
    expect(find.byType(ShareSheet), findsNothing);
    expect(h.shell.sourcesOpen, isTrue);
    await shares.close();
  });

  testWidgets('asking about shared text puts it, quoted, in a new chat', (
    tester,
  ) async {
    final shares = StreamController<SharedItem>();
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm, size: phone, shares: shares);
    await share(tester, shares, const SharedText('Service due in May.'));
    await tester.tap(inSheet(control('Ask about it')));
    await tester.pumpAndSettle();
    expect(find.byType(ShareSheet), findsNothing);
    // Nothing goes until the person asks.
    expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
    expect(h.chat.activeThread, isNull);
    expect(
      tester.widget<EditableText>(composerField).controller.text,
      '> Service due in May.\n\n',
    );
    await shares.close();
  });

  testWidgets('a shared file goes with the message, but not past 20 MB', (
    tester,
  ) async {
    final shares = StreamController<SharedItem>();
    final llm = planningServer();
    await pumpApp(tester, llm: llm, size: phone, shares: shares);
    await share(
      tester,
      shares,
      SharedFile('huge.pdf', 21 * 1024 * 1024, () async => [1]),
    );
    await tester.tap(inSheet(control('Ask about it')));
    await tester.pumpAndSettle();
    expect(inSheet(find.textContaining('20 MB at most')), findsOneWidget);
    await tester.tap(inSheet(control('Close')));
    await tester.pumpAndSettle();
    await share(
      tester,
      shares,
      SharedFile('quote.pdf', 4, () async => [1, 2, 3, 4]),
    );
    expect(inSheet(find.text('PDF')), findsOneWidget);
    await tester.tap(inSheet(control('Ask about it')));
    await tester.pumpAndSettle();
    expect(control('1 file attached. Review'), findsOneWidget);
    await share(
      tester,
      shares,
      SharedFile('notes.pdf', 4, () async => [1, 2, 3, 4]),
    );
    await tester.tap(inSheet(control('Add to documents')));
    await tester.pumpAndSettle();
    expect(llm.calls, contains('upload:notes.pdf'));
    await shares.close();
  });

  testWidgets(
    'a shared file that cannot be read stays in the sheet, with why',
    (tester) async {
      final shares = StreamController<SharedItem>();
      final llm = planningServer();
      await pumpApp(tester, llm: llm, size: phone, shares: shares);
      await share(
        tester,
        shares,
        SharedFile(
          'gone.pdf',
          4,
          () async => throw const FileSystemException(),
        ),
      );
      await tester.tap(inSheet(control('Ask about it')));
      await tester.pumpAndSettle();
      expect(
        inSheet(find.text('The shared file could not be read.')),
        findsOne,
      );
      expect(find.byType(ShareSheet), findsOneWidget);
      await shares.close();
    },
  );

  testWidgets('with no server the sheet says to connect first', (tester) async {
    final shares = StreamController<SharedItem>();
    final h = await pumpApp(
      tester,
      size: phone,
      connection: null,
      shares: shares,
    );
    await share(tester, shares, const SharedText('Notes'));
    expect(inSheet(find.textContaining('Connect to your')), findsOneWidget);
    await tester.tap(inSheet(control('Open Settings')));
    await tester.pumpAndSettle();
    expect(find.byType(ShareSheet), findsNothing);
    expect(h.shell.settingsOpen, isTrue);
    await shares.close();
  });

  testWidgets('Back puts the sheet away', (tester) async {
    final shares = StreamController<SharedItem>();
    final h = await pumpApp(
      tester,
      llm: planningServer(),
      size: phone,
      shares: shares,
    );
    await share(tester, shares, const SharedText('Notes'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(h.shell.shared, isNull);
    await shares.close();
  });
}
