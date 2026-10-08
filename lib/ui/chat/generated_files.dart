import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/outputs.dart';
import '../app_scope.dart';
import '../files/save_file.dart';
import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/tappable.dart';

/// The files and images an agent made with an answer. An image shows, read from the server with
/// the key as any other call is; a file is a chip that downloads it. Each saves through
/// [AppScope.save], and a failure shows as the chat's problem.
class GeneratedFiles extends StatelessWidget {
  const GeneratedFiles(this.files, {super.key});

  final List<GeneratedFile> files;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 8,
    children: [
      for (final file in files)
        file.isImage
            ? _MadeImage(file, key: ValueKey(file.storageName))
            : _MadeFile(file),
    ],
  );
}

/// Asks where to save [file], then reads and writes it there.
Future<void> _download(BuildContext context, GeneratedFile file) async {
  final chat = AppScope.of(context).chat;
  await saveFile(
    context,
    file.name,
    () => chat.fileBytes(file),
    failTitle: 'Could not save ${file.name}',
    report: chat.report,
  );
}

class _MadeFile extends StatelessWidget {
  const _MadeFile(this.file);

  final GeneratedFile file;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final size = file.size;
    return Tappable(
      label: 'Download ${file.name}',
      tooltip: 'Download',
      onTap: () => _download(context, file),
      radius: BorderRadius.circular(99),
      color: t.accentbg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon('download', size: IconSize.xs, color: t.accent),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.sans(12.5, color: t.accent),
              ),
            ),
            if (size != null) ...[
              const SizedBox(width: 6),
              Text(sizeText(size), style: Type.sans(12, color: t.muted)),
            ],
          ],
        ),
      ),
    );
  }
}

/// An image an agent made, drawn once its bytes arrive, or a [_MadeFile] when they cannot be
/// read or drawn.
class _MadeImage extends StatefulWidget {
  const _MadeImage(this.file, {super.key});

  final GeneratedFile file;

  @override
  State<_MadeImage> createState() => _MadeImageState();
}

class _MadeImageState extends State<_MadeImage> {
  /// The image's bytes, made once, so a rebuild draws the same [MemoryImage] rather than
  /// decoding it again.
  Future<Uint8List?>? _bytes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bytes ??= AppScope.of(context).chat
        .fileBytes(widget.file)
        .then((bytes) => bytes == null ? null : Uint8List.fromList(bytes));
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return FutureBuilder(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Text(
            'Loading ${widget.file.name}…',
            style: Type.sans(12.5, color: t.muted),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) return _MadeFile(widget.file);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: Image.memory(
                  bytes,
                  gaplessPlayback: true,
                  fit: BoxFit.contain,
                  semanticLabel: widget.file.name,
                  errorBuilder: (_, _, _) => _MadeFile(widget.file),
                ),
              ),
            ),
            IconBtn(
              'download',
              tooltip: 'Download ${widget.file.name}',
              onPressed: () => _download(context, widget.file),
              box: 30,
              size: IconSize.xs,
            ),
          ],
        );
      },
    );
  }
}
