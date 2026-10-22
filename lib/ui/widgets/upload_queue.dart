import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/upload.dart';
import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import 'buttons.dart';
import 'doc_details.dart';

class _Pending {
  _Pending(this.file);

  final UploadFile file;
  final details = DocDetailsController();
}

/// The files picked to add, which wait in a list, each with its own details and a remove
/// button, until Add sends them all through [onSend].
class UploadQueue extends StatefulWidget {
  const UploadQueue({
    super.key,
    required this.onSend,
    required this.onProblem,
    required this.trigger,
  });

  final Future<void> Function(List<UploadFile> files) onSend;
  final void Function(String title, String text) onProblem;

  /// What opens the file picker, given the way to open it, such as an Add a file button among
  /// others.
  final Widget Function(VoidCallback browse) trigger;

  @override
  State<UploadQueue> createState() => _UploadQueueState();
}

class _UploadQueueState extends State<UploadQueue> {
  final List<_Pending> _pending = [];

  @override
  void dispose() {
    _removeAll();
    super.dispose();
  }

  /// Lists [files], each replacing a waiting file of the same name.
  void _add(List<UploadFile> files) {
    setState(() {
      for (final file in files) {
        _remove(file.name);
        _pending.add(_Pending(file));
      }
    });
  }

  void _remove(String name) {
    for (final p in _pending.where((p) => p.file.name == name).toList()) {
      _pending.remove(p);
      p.details.dispose();
    }
  }

  void _clear() => setState(() => _removeAll());

  void _removeAll() {
    for (final p in _pending) {
      p.details.dispose();
    }
    _pending.clear();
  }

  Future<void> _send() async {
    final files = [for (final p in _pending) p.file.withMeta(p.details.meta)];
    _clear();
    await widget.onSend(files);
  }

  /// Opens the system's file picker and lists what is picked, or says why the picker would not
  /// open. Nothing is read until it is sent, and an unreadable file becomes a reason instead of
  /// an error.
  Future<void> _browse() async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles();
    } catch (error) {
      if (mounted) widget.onProblem('Could not open the file picker', '$error');
      return;
    }
    // The picker may outlast the place it was opened for, as when the server changes.
    if (!mounted) return;
    _add([
      for (final file in picked)
        UploadFile(
          name: file.name,
          read: () async {
            try {
              return await file.readAsBytes();
            } on Exception {
              throw const UnreadableFile('the file could not be read');
            }
          },
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      widget.trigger(_browse),
      if (_pending.isNotEmpty) ...[
        const SizedBox(height: 10),
        for (final p in _pending)
          _PendingRow(
            p,
            key: ObjectKey(p),
            onRemove: () => setState(() => _remove(p.file.name)),
          ),
        const SizedBox(height: 4),
        ActionRow([
          AppButton('Cancel', onPressed: _clear),
          AppButton(
            'Add ${plural(_pending.length, 'file', 'files')}',
            primary: true,
            onPressed: _send,
          ),
        ]),
      ],
    ],
  );
}

class _PendingRow extends StatelessWidget {
  const _PendingRow(this.pending, {super.key, required this.onRemove});

  final _Pending pending;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final name = pending.file.name;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIcon('doc', size: IconSize.xs, color: t.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.note(t.ink),
                ),
              ),
              IconBtn(
                'close',
                tooltip: 'Remove $name',
                box: 28,
                size: IconSize.xs,
                onPressed: onRemove,
              ),
            ],
          ),
          DocDetails(pending.details, titleHint: name, of: name),
        ],
      ),
    );
  }
}
