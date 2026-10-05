import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/upload.dart';
import '../tokens.dart';
import '../type.dart';
import 'dashed.dart';

/// What the zone says it takes and how, for the eye and for a screen reader, in the words of a
/// touch [platform] or a mouse one.
String _hint(TargetPlatform platform) => switch (platform) {
  TargetPlatform.android || TargetPlatform.iOS => 'Tap to choose files',
  _ => 'Drop files here, or click to browse',
};

/// A picked or dropped file, for [DropZone.onFiles]. Nothing is read until it is sent, and a
/// folder or an unreadable file becomes a reason instead of an error.
UploadFile _upload(XFile file) {
  Future<T> reading<T>(Future<T> Function() read) async {
    if (file is DropItemDirectory) {
      throw const UnreadableFile('it is a folder; upload the files inside it');
    }
    try {
      return await read();
    } on Exception {
      throw const UnreadableFile('the file could not be read');
    }
  }

  return UploadFile(name: file.name, read: () => reading(file.readAsBytes));
}

/// Drop files here, or click to browse.
class DropZone extends StatefulWidget {
  const DropZone({
    super.key,
    required this.onFiles,
    required this.onProblem,
    this.extensions,
  });

  /// The extensions the picker offers, with the dot, or null for any file. A drop takes any
  /// file; [onFiles] decides.
  final Set<String>? extensions;

  /// Sends the files.
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
      final extensions = widget.extensions;
      picked = await openFiles(
        acceptedTypeGroups: [
          if (extensions != null)
            XTypeGroup(
              label: 'Files the server reads',
              extensions: [for (final e in extensions) e.replaceFirst('.', '')],
            ),
        ],
      );
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
    final hint = _hint(Theme.of(context).platform);
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
          label: 'Add a file. $hint',
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
                      'Add a file',
                      style: Type.sans(
                        14,
                        weight: FontWeight.w500,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hint,
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
