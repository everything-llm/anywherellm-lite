import 'package:everything/core/documents.dart';
import 'package:everything/core/ports.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';

void main() {
  final doc = heldDoc;
  FakeAnythingLlm server() => documentServer();

  test('finds the document and the workspaces that hold it', () async {
    final llm = server();
    final view = await openDocument(llm, doc.path);
    expect(view.doc.title, 'agents');
    expect(view.holders.map((w) => w.slug), ['research']);
    expect(llm.calls, containsAll(['workspace:research', 'workspace:other']));
  });

  test('a missing document is a 404', () async {
    await expectLater(
      openDocument(server(), 'claude/gone.json'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
    );
  });

  test('a failed read is thrown as it is', () async {
    final llm = server()..errors['workspaces'] = const ApiException('down');
    await expectLater(
      openDocument(llm, doc.path),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'down')),
    );
  });
}
