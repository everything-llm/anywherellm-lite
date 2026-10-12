import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors.dart';
import '../../core/gallery.dart';
import '../app_scope.dart';
import '../files/save_file.dart';
import '../icons.dart';
import '../layout.dart';
import '../links.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/phone_page.dart';
import '../widgets/rise.dart';
import '../widgets/tappable.dart';
import 'answer_image.dart';

/// An answer's pictures in one row of four square tiles, so the row keeps its height whatever
/// the answer holds: past four, the fourth says how many more there are. A tile opens the
/// pictures one at a time ([GalleryPage]).
class Gallery extends StatelessWidget {
  const Gallery(this.pictures, {super.key});

  final List<Picture> pictures;

  static const _columns = 4;
  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shown = pictures.take(_columns).toList();
    final more = pictures.length - shown.length;
    return LayoutBuilder(
      builder: (context, box) {
        final side = (box.maxWidth - _gap * (_columns - 1)) / _columns;
        // Twice the tile's width, so a picture up to twice as wide as tall still covers it.
        final decode = (side * 2 * MediaQuery.devicePixelRatioOf(context))
            .round();
        return Row(
          spacing: _gap,
          children: [
            for (final (i, picture) in shown.indexed)
              SizedBox.square(
                dimension: side,
                child: _Tile(
                  picture,
                  decodeWidth: decode,
                  number: i + 1,
                  more: i == shown.length - 1 ? more : 0,
                  onTap: () => scope.shell.openGallery(
                    pictures,
                    i,
                    chat: scope.chat.title,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One square of a [Gallery]: the picture filling it, or its site where it did not load, and
/// over the last, how many [more] there are.
class _Tile extends StatelessWidget {
  const _Tile(
    this.picture, {
    required this.decodeWidth,
    required this.number,
    required this.more,
    required this.onTap,
  });

  final Picture picture;
  final int decodeWidth;
  final int number;
  final int more;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final caption = picture.caption.isEmpty ? 'Picture' : picture.caption;
    return Tappable(
      label: more > 0
          ? 'Picture $number and $more more'
          : 'Picture $number: $caption, from ${picture.site}',
      onTap: onTap,
      radius: BorderRadius.circular(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: t.hover),
            AnswerImage(
              picture.image,
              alt: picture.caption,
              server: scope.settings.connection?.uri,
              linked: true,
              fit: BoxFit.cover,
              decodeWidth: decodeWidth,
              unloaded: (context) => _Unloaded(picture, small: true),
            ),
            if (more > 0)
              ColoredBox(
                color: const Color(0xC7252836),
                child: Center(
                  child: Text(
                    '+$more',
                    style: Type.sans(
                      19,
                      weight: FontWeight.w600,
                      color: const Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What shows in a picture's place when it did not load: its site, and on the page, that it
/// did not load.
class _Unloaded extends StatelessWidget {
  const _Unloaded(this.picture, {this.small = false});

  final Picture picture;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      color: t.hover,
      padding: const EdgeInsets.all(6),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Text(
            picture.site,
            maxLines: small ? 3 : 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Type.mono(small ? 10.5 : 14, color: t.muted),
          ),
          if (!small)
            Text(
              'The picture did not load.',
              style: Type.sans(14, color: t.muted),
            ),
        ],
      ),
    );
  }
}

/// An answer's pictures one at a time, over the window: where it is in the set, the picture
/// whole in a frame that keeps its height, Previous and Next or a swipe, its caption and site,
/// Open page, Save and, where the device has a share sheet, Share.
class GalleryPage extends StatefulWidget {
  const GalleryPage(this.open, {super.key});

  final GalleryOpen open;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  late final _pages = PageController(initialPage: widget.open.index);
  late int _at = widget.open.index;

  List<Picture> get _pictures => widget.open.pictures;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int to) => unawaited(
    _pages.animateToPage(
      to,
      duration: motion(context, const Duration(milliseconds: 250)),
      curve: Curves.easeOutCubic,
    ),
  );

  void _close() => AppScope.of(context).shell.closePopup();

  /// The picture's bytes, or null when they cannot be read.
  Future<List<int>?> _bytes(Picture picture) async {
    try {
      return await AppScope.of(context).chat.imageBytes(picture.image);
    } on ApiException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final picture = _pictures[_at];
    final count = _pictures.length;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          if (_at > 0) _go(_at - 1);
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          if (_at < count - 1) _go(_at + 1);
        },
      },
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: t.bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PhonePageHeader(
                title: '${_at + 1} of $count',
                back: 'Back to the chat',
                onBack: _close,
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            spacing: 12,
                            children: [
                              Text(
                                'From this answer',
                                style: Type.sans(13, color: t.muted),
                              ),
                              Expanded(
                                child: Text(
                                  widget.open.chat,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: Type.sans(13, color: t.muted),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        _frame(context),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 2,
                            children: [
                              Text(
                                picture.caption.isEmpty
                                    ? picture.fileName
                                    : picture.caption,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Type.sans(
                                  16,
                                  weight: FontWeight.w600,
                                  color: t.ink,
                                ),
                              ),
                              Text(
                                picture.site,
                                style: Type.mono(13, color: t.muted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        ActionRow(even: true, [
                          AppButton(
                            'Open page',
                            primary: true,
                            onPressed: () => openLink(
                              context,
                              (picture.page ?? picture.image).toString(),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        ActionRow(even: true, [
                          AppButton(
                            'Save',
                            onPressed: () => unawaited(
                              saveFile(
                                context,
                                picture.fileName,
                                () => _bytes(picture),
                                failTitle: 'Could not save ${picture.fileName}',
                                report: scope.chat.report,
                              ),
                            ),
                          ),
                          if (scope.share != null)
                            AppButton(
                              'Share',
                              onPressed: () => unawaited(
                                shareFile(context, picture.fileName, () async {
                                  final bytes = await _bytes(picture);
                                  if (bytes == null) {
                                    scope.chat.report(
                                      'Could not share ${picture.fileName}',
                                      'The picture could not be read.',
                                    );
                                  }
                                  return bytes;
                                }),
                              ),
                            ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The pictures in a frame that keeps its height, swiped through, with Previous and Next.
  Widget _frame(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final count = _pictures.length;
    Widget step(String icon, String label, int to, {required bool left}) =>
        Positioned(
          top: 0,
          bottom: 0,
          left: left ? 8 : null,
          right: left ? null : 8,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: t.shadow,
                    blurRadius: 8,
                    spreadRadius: -2,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Tappable(
                label: label,
                tooltip: label,
                onTap: to < 0 || to >= count ? null : () => _go(to),
                shape: const CircleBorder(),
                color: t.panel,
                dimWhenDisabled: 0.4,
                child: SizedBox.square(
                  dimension: 44,
                  child: Center(
                    child: AppIcon(icon, size: IconSize.small, color: t.ink2),
                  ),
                ),
              ),
            ),
          ),
        );
    return Container(
      height: 390,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.panel,
        border: Border.all(color: t.line2),
        borderRadius: BorderRadius.circular(Sizes.phoneCard),
      ),
      child: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: count,
            onPageChanged: (i) => setState(() => _at = i),
            itemBuilder: (context, i) => SizedBox.expand(
              child: AnswerImage(
                _pictures[i].image,
                alt: _pictures[i].caption,
                server: scope.settings.connection?.uri,
                linked: true,
                maxHeight: 390,
                unloaded: (context) => _Unloaded(_pictures[i]),
              ),
            ),
          ),
          if (count > 1) ...[
            step('back', 'Previous picture', _at - 1, left: true),
            step('chevron', 'Next picture', _at + 1, left: false),
          ],
        ],
      ),
    );
  }
}
