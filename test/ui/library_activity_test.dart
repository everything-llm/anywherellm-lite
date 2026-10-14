import 'package:anywherellm/core/activity.dart';
import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/library.dart';
import 'package:anywherellm/core/outputs.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:anywherellm/ui/activity.dart';
import 'package:anywherellm/ui/chat/generated_files.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_toolkit.dart';
import '../support/pixels.dart';
import '../support/pump.dart';

FakeToolkit _serving(Set<String> features) =>
    FakeToolkit()
      ..served = {ToolkitFeature.memories, ToolkitFeature.jobs, ...features};

/// A Library with an app and two files in the open workspace, q3, and an app and a picture in
/// Household.
FakeToolkit _library() =>
    _serving({ToolkitFeature.library})
      ..libraryContents = LibraryContents(
        apps: [
          LibraryApp(
            title: 'Budget',
            page: '/apps-lean/b1.html',
            workspace: 'Q3 planning',
            workspaceSlug: 'q3',
            change: 'Added Rent',
            changed: DateTime.now().toUtc(),
          ),
          const LibraryApp(
            title: 'Groceries',
            page: '/apps-lean/g1.html',
            workspace: 'Household',
            workspaceSlug: 'household',
            change: 'Added Eggs',
          ),
        ],
        files: const [
          LibraryFile(
            file: GeneratedFile(
              type: 'PdfFileDownload',
              name: 'quote.pdf',
              storageName: 'pdf-1.pdf',
              size: 2048,
            ),
            workspace: 'Q3 planning',
            workspaceSlug: 'q3',
          ),
          LibraryFile(
            file: GeneratedFile(
              type: 'imageGenerationCard',
              name: 'cat.png',
              storageName: 'img-1.png',
            ),
            workspace: 'Household',
            workspaceSlug: 'household',
          ),
        ],
      );

Future<Harness> _open(
  WidgetTester tester,
  FakeToolkit toolkit, {
  FakeAnythingLlm? llm,
  bool canViewApps = false,
  bool canShare = false,
}) => pumpApp(
  tester,
  llm: llm ?? planningServer(),
  toolkitServer: toolkit,
  onChat: false,
  canViewApps: canViewApps,
  canShare: canShare,
  size: const Size(390, 1000),
);

ActivityEvent _event(
  String title, {
  String id = '',
  Duration ago = Duration.zero,
  ActivityKind kind = ActivityKind.task,
  ActivityOutcome outcome = ActivityOutcome.ok,
  String detail = '',
  ActivityLink? link,
}) => ActivityEvent(
  id: id.isEmpty ? null : id,
  at: DateTime.now().toUtc().subtract(ago),
  title: title,
  kind: kind,
  outcome: outcome,
  workspace: 'Household',
  detail: detail,
  link: link,
);

void main() {
  group('Library', () {
    testWidgets('a toolkit without it has no Library row', (tester) async {
      await _open(tester, FakeToolkit());
      expect(find.text('Library'), findsNothing);
      expect(find.text('Upcoming'), findsOneWidget);
    });

    testWidgets('the card counts what the open workspace has', (tester) async {
      await _open(tester, _library());
      expect(find.text('Library'), findsOneWidget);
      expect(find.text('1 app · 1 file'), findsOneWidget);
    });

    testWidgets('it shows the open workspace\'s, or every workspace\'s', (
      tester,
    ) async {
      final h = await _open(tester, _library());
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(h.shell.toolkitPage, isNotNull);
      expect(find.text('Budget'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
      expect(find.textContaining('Added Rent'), findsOneWidget);
      expect(find.text('Apps · 1'), findsOneWidget);
      await tester.tap(control('All workspaces'));
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Apps · 2'), findsOneWidget);
      expect(find.text('Files · 2'), findsOneWidget);
      await tester.tap(find.text('Files · 2'));
      await tester.pumpAndSettle();
      expect(find.text('quote.pdf'), findsOneWidget);
      expect(find.text('cat.png'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(h.shell.toolkitPage, isNull);
    });

    testWidgets('an app opens in its sheet, as an answer\'s link does', (
      tester,
    ) async {
      final h = await _open(tester, _library(), canViewApps: true);
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Budget'));
      await tester.pumpAndSettle();
      expect(
        find.text('Web view of https://h:3001/apps-lean/b1.html'),
        findsOneWidget,
      );
      expect(h.opened, isEmpty);
    });

    testWidgets('a file saves, and a picture opens over the window', (
      tester,
    ) async {
      final llm = planningServer()
        ..generated['pdf-1.pdf'] = [37, 80, 68, 70]
        ..generated['img-1.png'] = pixel;
      final h = await _open(tester, _library(), llm: llm, canShare: true);
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Files · 1'));
      await tester.pumpAndSettle();
      await tester.tap(control('Save quote.pdf'));
      await tester.pumpAndSettle();
      expect(h.saved['quote.pdf'], [37, 80, 68, 70]);
      // Its PDF has no preview; a picture in another workspace opens.
      await tester.tap(control('All workspaces'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('cat.png'));
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewer), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewer), findsNothing);
    });

    testWidgets('a read the toolkit refuses says why', (tester) async {
      final toolkit = _library()
        ..errors['library'] = const ApiException(
          'The toolkit did not accept the key.',
          status: 401,
        );
      final h = await _open(tester, toolkit);
      h.shell.openToolkitPage(ToolkitPage.library);
      await tester.pumpAndSettle();
      expect(find.text('Could not read the Library'), findsOneWidget);
      expect(find.textContaining('did not accept the key'), findsOneWidget);
      expect(control('Open Connection'), findsOneWidget);
    });

    testWidgets('a workspace with nothing says so', (tester) async {
      final toolkit = _serving({ToolkitFeature.library});
      await _open(tester, toolkit);
      expect(find.text('Nothing yet'), findsOneWidget);
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing here yet.'), findsOneWidget);
    });
  });

  group('Activity', () {
    FakeToolkit activity(List<ActivityEvent> events) =>
        _serving({ToolkitFeature.activity, ToolkitFeature.library})
          ..activityEvents = events;

    testWidgets('the card says what failed today', (tester) async {
      await _open(
        tester,
        activity([
          _event('Price watch', outcome: ActivityOutcome.failed),
          _event('Morning brief'),
        ]),
      );
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('1 failed today'), findsOneWidget);
    });

    testWidgets('events group by day and filter to what failed', (
      tester,
    ) async {
      final h = await _open(
        tester,
        activity([
          _event('Price watch', outcome: ActivityOutcome.failed),
          _event('Morning brief'),
          _event('Old brief', ago: const Duration(hours: 30)),
        ]),
      );
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(h.shell.toolkitPage, ToolkitPage.activity);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('Price watch'), findsOneWidget);
      expect(find.text('Old brief'), findsOneWidget);
      expect(find.text('Failed'), findsWidgets);
      await tester.tap(control('Failed'));
      await tester.pumpAndSettle();
      expect(find.text('Price watch'), findsOneWidget);
      expect(find.text('Morning brief'), findsNothing);
      expect(find.text('Old brief'), findsNothing);
    });

    testWidgets('older events come on Show more', (tester) async {
      final toolkit = activity([
        _event('One', id: 'a'),
        _event('Two', id: 'b'),
        _event('Three', id: 'c'),
      ])..activityPageSize = 2;
      await _open(tester, toolkit);
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(find.text('Three'), findsNothing);
      await tester.tap(control('Show more'));
      await tester.pumpAndSettle();
      expect(find.text('Three'), findsOneWidget);
      expect(control('Show more'), findsNothing);
      expect(toolkit.calls, contains('activity:b'));
    });

    testWidgets('an event opens in a sheet that leads to its chat', (
      tester,
    ) async {
      final h = await _open(
        tester,
        activity([
          _event(
            'Morning brief',
            detail: 'Done. The answer is in the chat.',
            link: const ChatLink('q3', 'budget'),
          ),
        ]),
      );
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Morning brief'));
      await tester.pumpAndSettle();
      expect(find.text('This run'), findsOneWidget);
      expect(find.text('Done. The answer is in the chat.'), findsOneWidget);
      await tester.tap(control('Open the chat'));
      await tester.pumpAndSettle();
      expect(h.shell.chatOpen, isTrue);
      expect(h.shell.toolkitPage, isNull);
      expect(h.chat.activeThread, 'budget');
    });

    testWidgets(
      'an event with a page opens it, and a file leads to the Library',
      (tester) async {
        final h = await _open(
          tester,
          activity([
            _event(
              'Groceries',
              kind: ActivityKind.app,
              link: const PageLink('/apps-lean/g1.html'),
            ),
            _event(
              'Quote.pdf',
              kind: ActivityKind.file,
              detail: 'An 84 KB PDF.',
            ),
          ]),
          canViewApps: true,
        );
        await tester.tap(find.text('Activity'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Groceries'));
        await tester.pumpAndSettle();
        await tester.tap(control('Open it'));
        await tester.pumpAndSettle();
        expect(
          find.text('Web view of https://h:3001/apps-lean/g1.html'),
          findsOneWidget,
        );
        h.shell.closePopup();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Quote.pdf'));
        await tester.pumpAndSettle();
        await tester.tap(control('Show in Library'));
        await tester.pumpAndSettle();
        expect(h.shell.toolkitPage, ToolkitPage.library);
      },
    );

    testWidgets('a read the toolkit refuses says why', (tester) async {
      final toolkit = activity(const [])
        ..errors['activity'] = const ApiException('The toolkit is busy.');
      final h = await _open(tester, toolkit);
      h.shell.openToolkitPage(ToolkitPage.activity);
      await tester.pumpAndSettle();
      expect(find.text('Could not read the activity'), findsOneWidget);
      expect(find.text('The toolkit is busy.'), findsOneWidget);
    });

    testWidgets('a page of nothing says so', (tester) async {
      final h = await _open(tester, activity(const []));
      h.shell.openToolkitPage(ToolkitPage.activity);
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing yet.'), findsOneWidget);
      expect(find.byType(ActivityPage), findsOneWidget);
    });
  });
}
