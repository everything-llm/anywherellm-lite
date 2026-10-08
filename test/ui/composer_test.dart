import 'dart:async';

import 'package:anywherellm/ui/chat/composer.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/material.dart';

import '../support/fake_api.dart';
import '../support/pixels.dart';
import '../support/pump.dart';

/// A file picker that picks [files], once [picked] completes when it is given.
class _Picker extends FileSelectorPlatform {
  _Picker(this.files, {this.picked});

  final List<XFile> files;
  final Future<void>? picked;

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    await picked;
    return files;
  }
}

/// A one-pixel `photo.png`.
XFile photo() => XFile.fromData(pixel, path: 'photo.png', length: pixel.length);

/// A one-byte `contract.pdf`.
XFile contract() =>
    XFile.fromData(Uint8List.fromList([1]), path: 'contract.pdf', length: 1);

/// The composer's drop target; Sources has its own.
final _composerDrop = find.descendant(
  of: find.byType(Composer),
  matching: find.byType(DropTarget),
);

/// Drops [files] on the composer, as a file manager does.
Future<void> drop(WidgetTester tester, List<DropItem> files) async {
  tester.widget<DropTarget>(_composerDrop).onDragDone!(
    DropDoneDetails(
      files: files,
      localPosition: Offset.zero,
      globalPosition: Offset.zero,
    ),
  );
  await tester.pumpAndSettle();
}

/// Ctrl+V in the composer, with [text] as the clipboard's text.
Future<void> paste(WidgetTester tester, {String text = ''}) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => switch (call.method) {
      'Clipboard.getData' => {'text': text},
      'Clipboard.hasStrings' => {'value': text.isNotEmpty},
      _ => null,
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  await tester.tap(composerField);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("a phone's keyboard starts the message with a capital", (
    tester,
  ) async {
    await pumpApp(tester);
    expect(
      tester.widget<EditableText>(composerField).textCapitalization,
      TextCapitalization.sentences,
    );
  });

  testWidgets('a picture shows small in the composer and in its question, '
      'and a document by its name', (tester) async {
    FileSelectorPlatform.instance = _Picker([photo(), contract()]);
    final llm = planningServer()..hold = true;
    await pumpApp(tester, llm: llm);
    await tester.tap(find.byTooltip('Attach files to this message'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('contract.pdf'), findsOneWidget);
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

  testWidgets(
    'files attached in one chat do not go with a message in another',
    (tester) async {
      FileSelectorPlatform.instance = _Picker([contract()]);
      final llm = planningServer();
      final h = await pumpApp(tester, llm: llm);
      await tester.tap(find.byTooltip('Attach files to this message'));
      await tester.pumpAndSettle();
      expect(find.text('contract.pdf'), findsOneWidget);
      await h.chat.select('household');
      await tester.pumpAndSettle();
      expect(find.text('contract.pdf'), findsNothing);
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
    FileSelectorPlatform.instance = _Picker([
      contract(),
    ], picked: picked.future);
    final h = await pumpApp(tester, llm: planningServer());
    await tester.tap(find.byTooltip('Attach files to this message'));
    await tester.pump();
    await h.chat.select('household');
    await tester.pumpAndSettle();
    picked.complete();
    await tester.pumpAndSettle();
    expect(find.text('contract.pdf'), findsNothing);
  });

  testWidgets('files dropped on the composer go with the next message', (
    tester,
  ) async {
    final llm = planningServer();
    await pumpApp(tester, llm: llm);
    await drop(tester, [
      DropItemFile.fromData(pixel, path: 'photo.png', length: pixel.length),
      DropItemDirectory('/home/me/notes', const [], name: 'notes'),
    ]);
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('notes is a folder'), findsOneWidget);
    await tester.enterText(composerField, 'What is this?');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 500));
    expect(llm.lastAttachments.map((a) => a.name), ['photo.png']);
  });

  testWidgets('nothing dropped is taken while a chat answers', (tester) async {
    final llm = planningServer()..hold = true;
    await pumpApp(tester, llm: llm);
    await tester.enterText(composerField, 'Hi');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<DropTarget>(_composerDrop).enable, isFalse);
  });

  testWidgets('Ctrl+V attaches a copied picture and leaves the message alone', (
    tester,
  ) async {
    final llm = planningServer();
    final h = await pumpApp(tester, llm: llm, canPasteImages: true)
      ..clipboardImage = pixel;
    await tester.enterText(composerField, 'Look');
    await paste(tester, text: 'not this');
    await paste(tester, text: 'not this');
    expect(find.text('Pasted image.png'), findsOneWidget);
    expect(find.text('Pasted image 2.png'), findsOneWidget);
    expect(h.chat.problem, isNull);
    expect(tester.widget<EditableText>(composerField).controller.text, 'Look');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 500));
    expect(llm.lastAttachments.map((a) => a.mime), ['image/png', 'image/png']);
  });

  testWidgets('Ctrl+V pastes text when the clipboard holds no picture', (
    tester,
  ) async {
    await pumpApp(tester, canPasteImages: true);
    await paste(tester, text: 'copied words');
    expect(
      tester.widget<EditableText>(composerField).controller.text,
      'copied words',
    );
    expect(find.textContaining('Pasted image'), findsNothing);
  });

  testWidgets("a picture from a phone keyboard's clipboard is attached", (
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
    expect(find.text('Pasted image.gif'), findsOneWidget);
  });

  group('the next question while an answer runs', () {
    Finder sendWhenDone() => find.byTooltip('Send when done');

    Future<FakeAnythingLlm> answering(WidgetTester tester) async {
      final llm = planningServer()..hold = true;
      await pumpApp(tester, llm: llm);
      await tester.enterText(composerField, 'First');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 300));
      return llm;
    }

    int sent(FakeAnythingLlm llm, String message) =>
        llm.calls.where((c) => c.endsWith(':$message')).length;

    testWidgets('can be typed, and is held to go when the answer ends', (
      tester,
    ) async {
      final llm = await answering(tester);
      expect(sendWhenDone(), findsNothing);
      await tester.enterText(composerField, 'Second');
      await tester.pump();
      expect(sendWhenDone(), findsOneWidget);
      await tester.tap(sendWhenDone());
      await tester.pump();
      expect(find.text('Sends when this answer ends.'), findsOneWidget);
      expect(sent(llm, 'Second'), 0);
      await llm.chat!.close();
      await tester.pump(const Duration(milliseconds: 300));
      expect(sent(llm, 'Second'), 1);
      expect(find.text('Sends when this answer ends.'), findsNothing);
      await llm.chat!.close();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('Enter holds it too, and Stop sends it', (tester) async {
      final llm = await answering(tester);
      await tester.enterText(composerField, 'Second');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('Sends when this answer ends.'), findsOneWidget);
      await tester.tap(find.byTooltip('Stop the answer'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(sent(llm, 'Second'), 1);
      await llm.chat!.close();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets("typing more or Don't send lets it go", (tester) async {
      final llm = await answering(tester);
      await tester.enterText(composerField, 'Second');
      await tester.pump();
      await tester.tap(sendWhenDone());
      await tester.pump();
      await tester.enterText(composerField, 'Second, longer');
      await tester.pump();
      expect(find.text('Sends when this answer ends.'), findsNothing);
      await tester.tap(sendWhenDone());
      await tester.pump();
      await tester.tap(find.bySemanticsLabel("Don't send"));
      await tester.pump();
      await llm.chat!.close();
      await tester.pump(const Duration(milliseconds: 300));
      expect(sent(llm, 'Second, longer'), 0);
      expect(find.text('Second, longer'), findsOneWidget);
    });

    testWidgets('another chat shown lets it go', (tester) async {
      final llm = await answering(tester);
      await tester.enterText(composerField, 'Second');
      await tester.pump();
      await tester.tap(sendWhenDone());
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Quarter priorities').first);
      await tester.pump(const Duration(milliseconds: 300));
      await llm.chat!.close();
      await tester.pump(const Duration(milliseconds: 300));
      expect(sent(llm, 'Second'), 0);
    });

    testWidgets('the box stays off while another chat answers', (tester) async {
      await answering(tester);
      await tester.tap(find.bySemanticsLabel('Quarter priorities').first);
      await tester.pump(const Duration(milliseconds: 300));
      // A field that is off is read only, so it is found by its type.
      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byType(Composer),
          matching: find.byType(TextField),
        ),
      );
      expect(field.enabled, isFalse);
    });
  });
}
