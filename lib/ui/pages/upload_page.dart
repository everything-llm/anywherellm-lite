import 'package:flutter/material.dart';

import '../../core/upload.dart';
import '../app_scope.dart';
import '../state/nav_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/drop_zone.dart';
import '../widgets/fields.dart';
import '../widgets/rows.dart';
import '../widgets/select.dart';
import 'page_frame.dart';

/// Sends files to the server, which reads them in as documents. Adding a document to a workspace
/// is done in AnythingLLM.
class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  @override
  void initState() {
    super.initState();
    AppScope.of(context).upload.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final upload = scope.upload;
    return ListenableBuilder(
      listenable: upload,
      builder: (context, _) {
        final accepted = upload.accepted;
        final sending = upload.sending;
        return PageFrame(
          children: [
            const PageHead(
              'Upload',
              sub:
                  'The server reads each file in as a document. Add it to a workspace in '
                  'AnythingLLM to chat over it.',
            ),
            NilsSelect(
              label: 'Folder',
              value: upload.folder,
              options: [
                for (final name in upload.folders)
                  (value: name, label: 'Folder: $name'),
              ],
              onChanged: upload.choose,
            ),
            DropZone(
              extensions: accepted,
              onFiles: upload.upload,
              onProblem: upload.report,
            ),
            if (accepted != null && accepted.isNotEmpty)
              HelpText(
                'The server reads ${(accepted.toList()..sort()).join(' ')}',
              ),
            if (sending != null)
              HelpText('Uploading $sending...', status: true),
            for (final problem in upload.problems)
              AlertBox(AlertKind.bad, problem.title, text: problem.text),
            if (upload.uploaded.isNotEmpty)
              ListSection('Uploaded', [
                for (final doc in upload.uploaded)
                  NilsRow(
                    title: doc.title,
                    meta: doc.folder,
                    leading: _Extension(doc.title),
                    onTap: () => scope.nav.go(DocumentRoute(doc.path)),
                  ),
              ]),
          ],
        );
      },
    );
  }
}

/// The file type, on a tile where a row's icon would go.
class _Extension extends StatelessWidget {
  const _Extension(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      width: 32,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.accentbg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        sourceExt(name),
        style: Type.sans(
          9.5,
          weight: FontWeight.w600,
          color: t.accent,
          letterSpacing: 0.29,
        ),
      ),
    );
  }
}
