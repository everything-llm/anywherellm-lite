import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/chat.dart';
import '../../core/gallery.dart';
import '../app_scope.dart';
import '../files/save_file.dart';
import '../icons.dart';
import '../layout.dart';
import '../settings/rows.dart';
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
    final server = scope.settings.connection?.uri;
    final pictures = [for (final picture in this.pictures) picture.on(server)];
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
            ColoredBox(color: t.sunken),
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
              // The dark theme's tile, in either theme, as a picture's frame is dark.
              ColoredBox(
                color: Tokens.dark.tile,
                child: Center(
                  child: Text('+$more', style: Type.title(Tokens.dark.ink)),
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
      color: t.sunken,
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
            style: Type.mono(small ? 11 : 15, color: t.muted),
          ),
          if (!small)
            Text('The picture did not load.', style: Type.body(t.muted)),
        ],
      ),
    );
  }
}

/// An answer's pictures one at a time, over the window: where it is in the set, the picture
/// whole in a frame that keeps its height, Previous and Next or a swipe, its caption and site,
/// Open page, and for a picture on the server's own host ([loadableImage]), Save and, where the
/// device has a share sheet, Share.
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

  void _go(int to) =>
      _pages.turnTo(context, to, const Duration(milliseconds: 250));

  void _close() => AppScope.of(context).shell.closePopup();

  @override
  Widget build(BuildContext context) {
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
          color: t.ground,
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
                      padding: Sizes.pagePadding,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            spacing: 12,
                            children: [
                              Text('From this answer', style: Type.note(t.ink)),
                              Expanded(
                                child: Text(
                                  widget.open.chat,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: Type.note(t.ink),
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
                                style: Type.body(
                                  t.ink,
                                  weight: FontWeight.w600,
                                ),
                              ),
                              Text(picture.site, style: Type.code(t.muted)),
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
                              picture.page ?? picture.image,
                            ),
                          ),
                        ]),
                        _PictureActions(picture),
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
    // At either end the step that goes nowhere stays, opaque: sunken, its arrow muted.
    Widget step(String icon, String label, int to, {required bool left}) {
      final can = to >= 0 && to < count;
      return Positioned(
        top: 0,
        bottom: 0,
        left: left ? 8 : null,
        right: left ? null : 8,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: can ? t.tileShadow : const [],
            ),
            child: Tappable(
              label: label,
              tooltip: label,
              onTap: can ? () => _go(to) : null,
              shape: CircleBorder(
                side: can ? BorderSide.none : BorderSide(color: t.line),
              ),
              color: can ? t.tile : t.sunken,
              child: SizedBox.square(
                dimension: Tappable.touchSide,
                child: Center(
                  child: AppIcon(
                    icon,
                    size: IconSize.small,
                    color: can ? t.ink : t.muted,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 390,
      clipBehavior: Clip.antiAlias,
      decoration: cardDecoration(t),
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

/// Save and, where the device has a share sheet, Share, for a [picture] on the server's own host
/// ([loadableImage]): only such a picture is read, as the client itself insists. A failure shows
/// through the chat's problem.
class _PictureActions extends StatelessWidget {
  const _PictureActions(this.picture);

  final Picture picture;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    if (!loadableImage(picture.image, scope.settings.connection?.uri)) {
      return const SizedBox.shrink();
    }
    final name = picture.fileName;
    Future<List<int>> bytes() => scope.chat.bytes.image(picture.image);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ActionRow(even: true, [
        AppButton(
          'Save',
          onPressed: () => unawaited(
            saveFile(
              context,
              name,
              bytes,
              failTitle: 'Could not save $name',
              report: scope.chat.report,
            ),
          ),
        ),
        if (scope.share != null)
          AppButton(
            'Share',
            onPressed: () => unawaited(shareFile(context, name, bytes)),
          ),
      ]),
    );
  }
}
