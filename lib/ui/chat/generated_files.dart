import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/outputs.dart';
import '../../core/upload.dart';
import '../app_scope.dart';
import '../files/save_file.dart';
import '../sources/sources_panel.dart';
import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/sheet.dart';
import '../widgets/tappable.dart';

/// The files and images an agent made with an answer. An image shows, read from the server with
/// the key as any other call is, under a line naming its type and size, with Save and, where
/// the device can share, Share; tapped, it opens over the window. A file is a card with its
/// type, name and size and Save. Each saves through [AppScope.save], and a failure shows as the
/// chat's problem.
class GeneratedFiles extends StatelessWidget {
  const GeneratedFiles(this.files, {super.key});

  final List<GeneratedFile> files;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final file in files)
        file.isImage
            ? _MadeImage(file, key: ValueKey(file.storageName))
            : _MadeFile(file, key: ValueKey(file.storageName)),
    ],
  );
}

/// Asks where to save [file], then reads and writes it there. Says whether it was saved.
Future<bool> saveMadeFile(BuildContext context, GeneratedFile file) async {
  final chat = AppScope.of(context).chat;
  final where = await saveFile(
    context,
    file.name,
    () => chat.fileBytes(file),
    failTitle: 'Could not save ${file.name}',
    report: chat.report,
  );
  return where != null;
}

/// Save, which asks where to save [file] and saves it, reading Saved once the file is saved.
class _SaveButton extends StatefulWidget {
  const _SaveButton(this.file);

  final GeneratedFile file;

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final name = widget.file.name;
    return Tappable(
      touchTarget: true,
      label: _saved ? 'Saved $name' : 'Save $name',
      tooltip: _saved ? null : 'Save',
      onTap: () async {
        final saved = await saveMadeFile(context, widget.file);
        if (mounted && saved) setState(() => _saved = true);
      },
      radius: BorderRadius.circular(8),
      child: SizedBox(
        height: 32,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                _saved ? 'check' : 'download',
                size: IconSize.xs,
                color: t.accent,
              ),
              const SizedBox(width: 6),
              Text(
                _saved ? 'Saved' : 'Save',
                style: Type.sans(
                  13.5,
                  weight: FontWeight.w500,
                  color: t.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A file an agent made: a card with its type, name and size and Save.
class _MadeFile extends StatelessWidget {
  const _MadeFile(this.file, {super.key});

  final GeneratedFile file;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final size = file.size;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        decoration: BoxDecoration(
          color: t.panel,
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TypeTile.label(sourceExt(file.name)),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(14, weight: FontWeight.w500, color: t.ink),
                  ),
                  if (size != null)
                    Text(sizeText(size), style: Type.sans(12, color: t.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _SaveButton(file),
          ],
        ),
      ),
    );
  }
}

/// An image an agent made, drawn once its bytes arrive, or a [_MadeFile] when they cannot be
/// read or drawn. Tapped, it opens over the window.
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
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final file = widget.file;
    return FutureBuilder(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Text(
            'Loading ${file.name}…',
            style: Type.sans(12.5, color: t.muted),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) return _MadeFile(file);
        final size = file.size ?? bytes.length;
        final image = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Tappable(
              label: 'Open ${file.name}',
              onTap: () => scope.shell.togglePopup(file),
              radius: BorderRadius.circular(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: Image.memory(
                    bytes,
                    gaplessPlayback: true,
                    fit: BoxFit.contain,
                    cacheHeight: (360 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                    semanticLabel: file.name,
                    errorBuilder: (_, _, _) => _MadeFile(file),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text(
                  'Image · ${sourceExt(file.name)} · ${sizeText(size)}',
                  style: Type.sans(12.5, color: t.muted),
                ),
                _SaveButton(file),
                if (scope.share != null)
                  IconBtn(
                    'share',
                    tooltip: 'Share ${file.name}',
                    onPressed: () => shareFile(
                      context,
                      file.name,
                      () => AppScope.of(context).chat.fileBytes(file),
                    ),
                    box: 30,
                    size: IconSize.xs,
                  ),
              ],
            ),
          ],
        );
        return ViewerWhileOpen(file, bytes, child: image);
      },
    );
  }
}

/// [child], with [ImageViewer] showing [file] over the window while it is the popup open, keyed
/// by the file, so Esc and Back close it.
class ViewerWhileOpen extends StatelessWidget {
  const ViewerWhileOpen(
    this.file,
    this.bytes, {
    super.key,
    required this.child,
  });

  final GeneratedFile file;
  final Uint8List bytes;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    return ValueListenableBuilder(
      valueListenable: shell.popup,
      child: child,
      builder: (context, popup, child) => OverlayWhile(
        open: identical(popup, file),
        overlay: (context) => SafeArea(
          child: ImageViewer(
            file,
            bytes,
            onClose: () => shell.closePopup(file),
          ),
        ),
        child: child!,
      ),
    );
  }
}

/// An image an agent made, [file] holding [bytes], over the whole window on a dark ground, to
/// pinch and pan: its name and Close, then Save and, where the device can share, Share.
class ImageViewer extends StatelessWidget {
  const ImageViewer(this.file, this.bytes, {super.key, required this.onClose});

  final GeneratedFile file;
  final Uint8List bytes;
  final VoidCallback onClose;

  static const _ground = Color(0xFF101018);

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final light = Colors.white;
    Widget button(
      String label,
      String icon,
      VoidCallback onTap, {
      required bool filled,
    }) => Expanded(
      child: Tappable(
        label: label,
        onTap: onTap,
        radius: BorderRadius.circular(12),
        color: filled ? light : Colors.transparent,
        side: filled
            ? null
            : BorderSide(color: light.withValues(alpha: 0.55), width: 1.5),
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(
                icon,
                size: IconSize.small,
                color: filled ? _ground : light,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Type.sans(
                  15.5,
                  weight: FontWeight.w600,
                  color: filled ? _ground : light,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
      child: Focus(
        autofocus: true,
        child: Semantics(
          container: true,
          scopesRoute: true,
          explicitChildNodes: true,
          label: 'Image',
          child: ColoredBox(
            color: _ground,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 60,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Type.sans(
                              15,
                              weight: FontWeight.w500,
                              color: light,
                            ),
                          ),
                        ),
                        Tappable(
                          label: 'Close',
                          tooltip: 'Close',
                          onTap: onClose,
                          radius: BorderRadius.circular(10),
                          child: SizedBox.square(
                            dimension: 44,
                            child: Center(
                              child: AppIcon(
                                'close',
                                size: IconSize.small,
                                color: light,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    maxScale: 5,
                    child: Center(
                      child: Image.memory(
                        bytes,
                        gaplessPlayback: true,
                        fit: BoxFit.contain,
                        semanticLabel: file.name,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  child: Row(
                    spacing: 8,
                    children: [
                      button(
                        'Save',
                        'download',
                        () => saveMadeFile(context, file),
                        filled: true,
                      ),
                      if (scope.share != null)
                        button(
                          'Share',
                          'share',
                          () => shareFile(
                            context,
                            file.name,
                            () => AppScope.of(context).chat.fileBytes(file),
                          ),
                          filled: false,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
