import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../state/inbox_controller.dart';
import '../tokens.dart';
import '../type.dart';
import 'dashed.dart';

/// What the zone says it takes and how, for the eye and for a screen reader.
const _hint = 'Drop .md files here, or click to browse';

const _markdown = XTypeGroup(
  label: 'Markdown',
  extensions: ['md'],
  mimeTypes: ['text/markdown'],
);

/// A picked or dropped file, for [DropZone.onFiles]. Nothing is read until it is staged,
/// and a folder or an unreadable file becomes a reason instead of an error.
UploadFile _upload(XFile file) {
  Future<T> reading<T>(Future<T> Function() read) async {
    if (file is DropItemDirectory) {
      throw const UnreadableFile(
        'it is a folder; stage the .md files inside it',
      );
    }
    try {
      return await read();
    } on Exception {
      throw const UnreadableFile('the file could not be read');
    }
  }

  return UploadFile(
    name: file.name,
    length: () => reading(file.length),
    read: () => reading(file.readAsBytes),
  );
}

/// Drop `.md` files here, or click to browse.
class DropZone extends StatefulWidget {
  const DropZone({super.key, required this.onFiles, required this.onProblem});

  /// Stages the files.
  final Future<void> Function(List<UploadFile> files) onFiles;

  /// Reports a failure that is not about one file.
  final void Function(String title, String text) onProblem;

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _over = false;
  bool _hover = false;
  bool _focused = false;

  Future<void> _browse() async {
    final List<XFile> picked;
    try {
      picked = await openFiles(acceptedTypeGroups: const [_markdown]);
    } catch (error) {
      widget.onProblem('Could not open the file picker', '$error');
      return;
    }
    await widget.onFiles(picked.map(_upload).toList());
  }

  Future<void> _dropped(DropDoneDetails details) async {
    setState(() => _over = false);
    await widget.onFiles(details.files.map(_upload).toList());
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final lit = _over || _hover || _focused;
    return DropTarget(
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: _dropped,
      // A button to the keyboard too: Tab reaches it, and Enter or Space opens the picker.
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (on) => setState(() => _hover = on),
        onShowFocusHighlight: (on) => setState(() => _focused = on),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _browse(),
          ),
        },
        child: Semantics(
          button: true,
          label: 'Stage a file. $_hint',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: _browse,
            behavior: HitTestBehavior.opaque,
            child: DashedBox(
              color: lit ? t.accent : t.line,
              radius: 12,
              width: 1.5,
              fill: lit ? t.accentbg : null,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    Text(
                      'Stage a file',
                      style: Type.sans(
                        14,
                        weight: FontWeight.w500,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _hint,
                      textAlign: TextAlign.center,
                      style: Type.sans(12.5, color: t.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
