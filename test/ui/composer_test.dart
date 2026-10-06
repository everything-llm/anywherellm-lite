import 'dart:async';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
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

/// A one-byte `contract.pdf`.
XFile contract() =>
    XFile.fromData(Uint8List.fromList([1]), path: 'contract.pdf', length: 1);

void main() {
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
}
