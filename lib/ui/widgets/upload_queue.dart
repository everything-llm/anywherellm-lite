import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/upload.dart';
import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import 'buttons.dart';
import 'doc_details.dart';
import 'drop_zone.dart';

class _Pending {
  _Pending(this.file);

  final UploadFile file;
  final details = DocDetailsController();
}

/// A [DropZone] whose files wait in a list, each with its own details and a remove button,
/// until Add sends them all through [onSend].
class UploadQueue extends StatefulWidget {
  const UploadQueue({
    super.key,
    required this.onSend,
    required this.onProblem,
    this.trigger,
  });

  final Future<void> Function(List<UploadFile> files) onSend;
  final void Function(String title, String text) onProblem;

  /// What stands in place of the [DropZone], given the way to open the file picker, such as an
  /// Add a file button among others. Files dropped on it wait as well.
  final Widget Function(VoidCallback browse)? trigger;

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
  Future<void> _add(List<UploadFile> files) async {
    if (!mounted) return;
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

  Widget _trigger(Widget Function(VoidCallback browse) trigger) => DropTarget(
    onDragDone: (details) => _add(details.files.map(uploadOf).toList()),
    child: trigger(
      () => browseFiles(this, onFiles: _add, onProblem: widget.onProblem),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      switch (widget.trigger) {
        final trigger? => _trigger(trigger),
        null => DropZone(onFiles: _add, onProblem: widget.onProblem),
      },
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
                  style: Type.sans(13.5, color: t.ink),
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
