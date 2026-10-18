import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../icons.dart';
import '../settings/rows.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';

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
    final plus = AppIcon('plus', size: IconSize.small, color: t.ink2);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          if (attached.isNotEmpty)
            FieldCard([
              for (final a in attached)
                Container(
                  constraints: const BoxConstraints(minHeight: Sizes.cardRow),
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
          FieldCard([
            if (onPhotos case final onPhotos?)
              CardRow(
                'Photo library',
                icon: 'image',
                onTap: onPhotos,
                trailing: plus,
              ),
            if (onCamera case final onCamera?)
              CardRow(
                'Take a photo',
                icon: 'camera',
                onTap: onCamera,
                trailing: plus,
              ),
            CardRow('Files', icon: 'attach', onTap: onFiles, trailing: plus),
          ]),
          ActionRow(even: true, [
            AppButton('Done', primary: true, onPressed: onDone),
          ]),
        ],
      ),
    );
  }
}
