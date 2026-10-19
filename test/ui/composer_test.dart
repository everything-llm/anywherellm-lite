import 'dart:async';

import 'package:anywherellm/core/chat.dart' show ChatMode;
import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/ui/chat/composer.dart';
import 'package:anywherellm/ui/widgets/sheet.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker_platform_interface/file_picker_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/material.dart';

import '../support/fake_api.dart';
import '../support/picker.dart';
import '../support/pixels.dart';
import '../support/pump.dart';

/// A one-pixel `photo.png`.
XFile photo() => XFile.fromData(pixel, path: 'photo.png', length: pixel.length);

/// A one-byte `contract.pdf`, as the file picker gives it.
PlatformFile contract() => Picked('contract.pdf');

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(SheetFrame), matching: f);

/// Attaches what the file picker gives, through the Attach sheet's Files.
Future<void> attachFiles(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add files or shortcuts to this message'));
  await tester.pumpAndSettle();
  await tester.tap(control('Files'));
  await tester.pumpAndSettle();
  await tester.tap(control('Done'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("on a phone Enter doesn't send; Send does", (tester) async {
    final llm = planningServer();
    await pumpApp(tester, enterSends: false, llm: llm);
    await tester.enterText(composerField, 'one');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(llm.calls.where((c) => c.startsWith('streamChat')), isEmpty);
    expect(composerText(tester), startsWith('one'));
    await tester.tap(control('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(llm.calls.where((c) => c.startsWith('streamChat')), hasLength(1));
  });

  testWidgets("the keyboard starts the message with a capital", (tester) async {
    await pumpApp(tester);
    expect(
      tester.widget<EditableText>(composerField).textCapitalization,
      TextCapitalization.sentences,
    );
  });

  testWidgets('a picture shows small in its question, and a document by its '
      'name', (tester) async {
    FilePickerPlatform.instance = FakePicker([
      Picked('photo.png', pixel),
      contract(),
    ]);
    final llm = planningServer()..hold = true;
    await pumpApp(tester, llm: llm);
    await attachFiles(tester);
    expect(control('2 files attached. Review'), findsOneWidget);
    await tester.enterText(composerField, 'What is this?');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    // The new turns rise into view from nothing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.bySemanticsLabel('photo.png'), findsOneWidget);
    expect(find.text('photo.png'), findsNothing);
    expect(find.text('contract.pdf'), findsOneWidget);
  });

  testWidgets('a document sent in the agent\'s mode goes in chat mode', (
    tester,
  ) async {
    FilePickerPlatform.instance = FakePicker([Picked('page.html')]);
    final llm = planningServer();
    await pumpApp(tester, llm: llm);
    await attachFiles(tester);
    await tester.enterText(composerField, 'What is on this page?');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 500));
    expect(llm.lastAttachments.map((a) => a.name), ['page.html']);
    expect(llm.lastMode, ChatMode.chat);
  });

  testWidgets(
    'files attached in one chat do not go with a message in another',
    (tester) async {
      FilePickerPlatform.instance = FakePicker([contract()]);
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm);
      await attachFiles(tester);
      expect(control('1 file attached. Review'), findsOneWidget);
      await h.chat.select('household');
      await tester.pumpAndSettle();
      expect(control('1 file attached. Review'), findsNothing);
      await tester.enterText(composerField, 'Hi');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 500));
      expect(llm.calls.where((c) => c.startsWith('streamChat')), isNotEmpty);
      expect(llm.lastAttachments, isEmpty);
    },
  );

  testWidgets('files picked while another chat was opened are not attached', (
    tester,
  ) async {
    final picked = Completer<void>();
    FilePickerPlatform.instance = FakePicker([
      contract(),
    ], picked: picked.future);
    final h = await pumpApp(tester, llm: planningServer());
    await tester.tap(find.byTooltip('Add files or shortcuts to this message'));
    await tester.pumpAndSettle();
    await tester.tap(control('Files'));
    await tester.pump();
    await h.chat.select('household');
    await tester.pumpAndSettle();
    picked.complete();
    await tester.pumpAndSettle();
    expect(_inSheet(find.text('contract.pdf')), findsNothing);
  });

  testWidgets("a picture from the keyboard's clipboard is attached", (
    tester,
  ) async {
    await pumpApp(tester);
    final field = tester.state<EditableTextState>(composerField);
    field.insertContent(
      KeyboardInsertedContent(
        mimeType: 'image/gif',
        uri: 'content://keyboard/1',
        data: pixel,
      ),
    );
    await tester.pumpAndSettle();
    expect(control('1 file attached. Review'), findsOneWidget);
    await tester.tap(control('1 file attached. Review'));
    await tester.pumpAndSettle();
    expect(_inSheet(find.text('Pasted image.gif')), findsOneWidget);
  });

  group('the next question while an answer runs', () {
    Finder sendWhenDone() => find.byTooltip('Send when done');

    Future<(Harness, FakeAnythingLlm)> answering(WidgetTester tester) async {
      final llm = planningServer()..hold = true;
      final h = await pumpApp(tester, llm: llm);
      await tester.enterText(composerField, 'First');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 300));
      return (h, llm);
    }

    int sent(FakeAnythingLlm llm, String message) =>
        llm.calls.where((c) => c.endsWith(':$message')).length;

    /// Types [text] and puts it after the messages waiting.
    Future<void> queue(WidgetTester tester, String text) async {
      await tester.enterText(composerField, text);
      await tester.pump();
      await tester.tap(sendWhenDone());
      await tester.pump();
    }

    String typed(WidgetTester tester) =>
        tester.widget<EditableText>(composerField).controller.text;

    testWidgets('each waits its turn, to go when the answer before it ends', (
      tester,
    ) async {
      final (_, llm) = await answering(tester);
      expect(sendWhenDone(), findsNothing);
      await tester.enterText(composerField, 'Second');
      await tester.pump();
      expect(sendWhenDone(), findsOneWidget);
      await tester.tap(sendWhenDone());
      await tester.pump();
      expect(typed(tester), isEmpty);
      expect(find.text('Sends when this answer ends.'), findsOneWidget);
      await queue(tester, 'Third');
      expect(
        find.text('Each sends in turn, when the answer before it ends.'),
        findsOneWidget,
      );
      expect(find.text('Second'), findsOneWidget);
      expect(find.text('Third'), findsOneWidget);
      expect(sent(llm, 'Second'), 0);

      await llm.chat!.close();
      await tester.pump(const Duration(milliseconds: 300));
      expect(sent(llm, 'Second'), 1);
      expect(sent(llm, 'Third'), 0);
      expect(find.text('Sends when this answer ends.'), findsOneWidget);

      await llm.chat!.close();
      await tester.pump(const Duration(milliseconds: 300));
      expect(sent(llm, 'Third'), 1);
      expect(find.text('Sends when this answer ends.'), findsNothing);
      await llm.chat!.close();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('Enter queues it too, and Stop sends the next', (tester) async {
      final (_, llm) = await answering(tester);
      await tester.enterText(composerField, 'Second');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('Sends when this answer ends.'), findsOneWidget);
      expect(typed(tester), isEmpty);
      await tester.tap(find.byTooltip('Stop the answer'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(sent(llm, 'Second'), 1);
      await llm.chat!.close();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets("Don't send takes one out, and typing keeps the rest", (
      tester,
    ) async {
      final (_, llm) = await answering(tester);
      await queue(tester, 'Second');
      await queue(tester, 'Third');
      await tester.enterText(composerField, 'Not yet');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel("Don't send Second"));
      await tester.pump();
      expect(find.text('Second'), findsNothing);
      await llm.chat!.close();
      await tester.pump(const Duration(milliseconds: 300));
      expect(sent(llm, 'Second'), 0);
      expect(sent(llm, 'Third'), 1);
      expect(typed(tester), 'Not yet');
      await llm.chat!.close();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('they go on while another chat shows', (tester) async {
      final (h, llm) = await answering(tester);
      final thread = h.chat.activeThread!;
      await queue(tester, 'Second');
      await h.chat.open('priorities');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Sends when this answer ends.'), findsNothing);
      await llm.chat!.close();
      await tester.pump(const Duration(milliseconds: 300));
      expect(sent(llm, 'Second'), 1);
      expect(h.chat.isAnswering(thread), isTrue);
      expect(h.chat.answeringHere, isFalse);
      await llm.chat!.close();
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.chat.isReady(thread), isTrue);
    });

    testWidgets(
      'while they wait for an answer the server writes, Send alone queues',
      (tester) async {
        final (h, llm) = await answering(tester);
        await queue(tester, 'Second');
        llm.chat!.addError(const CutOff('The connection dropped'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(composerField, 'Third');
        await tester.pump();
        expect(sendWhenDone(), findsNothing);
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();
        expect(typed(tester), isEmpty);
        expect(find.text('Third'), findsOneWidget);
        expect(sent(llm, 'Third'), 0);

        // The server saves the answer, which ends the reading for it.
        final thread = h.chat.activeThread!;
        llm.saveExchange(thread, 'First', 'Done');
        await tester.pump(const Duration(seconds: 5));
        await tester.pump();
        expect(sent(llm, 'Second'), 1);
      },
    );

    testWidgets('/reset is not queued, since it asks first', (tester) async {
      await answering(tester);
      await tester.enterText(composerField, '/reset');
      await tester.pump();
      expect(sendWhenDone(), findsNothing);
    });

    /// The composer's field, found by its type, since a field that is off is read only.
    TextField field(WidgetTester tester) => tester.widget<TextField>(
      find.descendant(
        of: find.byType(Composer),
        matching: find.byType(TextField),
      ),
    );

    testWidgets(
      'another chat of the workspace takes a message while one answers',
      (tester) async {
        final (h, llm) = await answering(tester);
        await h.chat.open('priorities');
        await tester.pump(const Duration(milliseconds: 300));
        expect(field(tester).enabled, isTrue);
        expect(field(tester).decoration!.hintText, 'Ask anything…');
        await tester.enterText(composerField, 'Second');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump(const Duration(milliseconds: 300));
        expect(sent(llm, 'Second'), 1);
        expect(h.chat.answeringHere, isTrue);
      },
    );

    testWidgets('a chat of another workspace takes a message', (tester) async {
      final llm = planningServer()..hold = true;
      final h = await pumpApp(tester, llm: llm);
      await tester.enterText(composerField, 'First');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 300));
      await h.chat.select('household');
      await tester.pump(const Duration(milliseconds: 300));
      expect(field(tester).enabled, isTrue);
      await tester.enterText(composerField, 'Second');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 300));
      expect(sent(llm, 'Second'), 1);
      expect(h.chat.answeringIn('q3'), isTrue);
    });
  });

  group('the Attach sheet', () {
    testWidgets('opening it puts the keyboard away', (tester) async {
      await pumpApp(tester, llm: planningServer());
      await tester.pumpAndSettle();
      await tester.tap(composerField);
      await tester.pump();
      expect(focused(tester, composerField), isTrue);
      await tester.tap(
        find.byTooltip('Add files or shortcuts to this message'),
      );
      await tester.pumpAndSettle();
      expect(focused(tester, composerField), isFalse);
    });

    testWidgets(
      'Attach opens a sheet that lists the files and takes them off',
      (tester) async {
        FilePickerPlatform.instance = FakePicker([contract()]);
        await pumpApp(tester, llm: planningServer());
        await tester.tap(
          find.byTooltip('Add files or shortcuts to this message'),
        );
        await tester.pumpAndSettle();
        // No photos on this device: Files alone.
        expect(_inSheet(find.text('Photo library')), findsNothing);
        await tester.tap(control('Files'));
        await tester.pumpAndSettle();
        expect(_inSheet(find.text('contract.pdf')), findsOneWidget);
        await tester.tap(control('Done'));
        await tester.pumpAndSettle();
        expect(find.byType(SheetFrame), findsNothing);
        // The composer keeps its height: one pill says how many go along.
        expect(find.text('contract.pdf'), findsNothing);
        expect(control('1 file attached. Review'), findsOneWidget);
        await tester.tap(control('1 file attached. Review'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Remove contract.pdf'));
        await tester.pumpAndSettle();
        expect(_inSheet(find.text('contract.pdf')), findsNothing);
        await tester.tap(control('Done'));
        await tester.pumpAndSettle();
        expect(control('1 file attached. Review'), findsNothing);
      },
    );

    testWidgets(
      'the sheet adds from the photos and says when the camera fails',
      (tester) async {
        final h = await pumpApp(
          tester,
          llm: planningServer(),
          canPickPhotos: true,
        );
        h.photos!
          ..chosen = [photo()]
          ..cameraFails = true;
        await tester.tap(
          find.byTooltip('Add files or shortcuts to this message'),
        );
        await tester.pumpAndSettle();
        await tester.tap(control('Photo library'));
        await tester.pumpAndSettle();
        expect(_inSheet(find.text('photo.png')), findsOneWidget);
        await tester.tap(control('Take a photo'));
        await tester.pumpAndSettle();
        await tester.tap(control('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Could not attach'), findsOneWidget);
        expect(find.textContaining('The camera did not open'), findsOneWidget);
        expect(control('1 file attached. Review'), findsOneWidget);
      },
    );
  });
}
