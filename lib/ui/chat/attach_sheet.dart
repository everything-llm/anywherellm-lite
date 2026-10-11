import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../icons.dart';
import '../settings/rows.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/tappable.dart';

/// A phone's Attach sheet: the files [attached] to the next message, each with Remove, then
/// where to add more from. [onPhotos] and [onCamera] are null where the device has no photos to
/// offer.
class AttachSheet extends StatelessWidget {
  const AttachSheet({
    super.key,
    required this.attached,
    required this.onRemove,
    required this.onFiles,
    required this.onDone,
    this.onPhotos,
    this.onCamera,
  });

  final List<Attachment> attached;
  final ValueChanged<Attachment> onRemove;
  final VoidCallback? onPhotos;
  final VoidCallback? onCamera;
  final VoidCallback onFiles;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          if (attached.isNotEmpty)
            FieldCard(inSheet: true, [
              for (final a in attached)
                Container(
                  constraints: const BoxConstraints(minHeight: 64),
                  padding: const EdgeInsets.only(
                    left: FieldCard.inset,
                    right: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          a.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Type.sans(17, color: t.ink),
                        ),
                      ),
                      IconBtn(
                        'close',
                        tooltip: 'Remove ${a.name}',
                        box: 44,
                        size: IconSize.small,
                        onPressed: () => onRemove(a),
                      ),
                    ],
                  ),
                ),
            ]),
          FieldCard(inSheet: true, [
            if (onPhotos case final onPhotos?)
              _AddRow('Photo library', onPhotos),
            if (onCamera case final onCamera?)
              _AddRow('Take a photo', onCamera),
            _AddRow('Files', onFiles),
          ]),
          ActionRow(even: true, [
            AppButton('Done', primary: true, onPressed: onDone),
          ]),
        ],
      ),
    );
  }
}

/// A place to add files from, with a plus at its end.
class _AddRow extends StatelessWidget {
  const _AddRow(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: label,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: FieldCard.inset),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: Type.sans(17, color: t.ink)),
            ),
            AppIcon('plus', size: IconSize.small, color: t.ink2),
          ],
        ),
      ),
    );
  }
}
