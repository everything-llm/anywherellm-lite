import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../../core/ports.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../links.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/tappable.dart';

/// An image in an answer: loaded when it is on the [server]'s host over https, a path from the
/// root ([onServer]) included; otherwise its description. The
/// description says whether the image was not loaded or failed to load, and why it failed. It
/// opens the image's address when tapped, unless the image is [linked], where the link around
/// it takes the tap.
class AnswerImage extends StatefulWidget {
  const AnswerImage(
    this.written, {
    super.key,
    required this.alt,
    required this.server,
    required this.linked,
    this.maxHeight = 360,
    this.fit = BoxFit.contain,
    this.unloaded,
    this.decodeWidth,
  });

  /// The image's address as the answer wrote it.
  final Uri written;

  /// The image's address, a path from the root on the [server] ([onServer]).
  Uri get uri => onServer(written, server);
  final String? alt;
  final Uri? server;

  /// Whether the image sits inside a link, which then takes a tap on its description.
  final bool linked;

  /// The tallest it is drawn.
  final double maxHeight;

  /// How the image fills its box: whole ([BoxFit.contain]) and rounded, or with
  /// [BoxFit.cover] filling it to its edges, as a gallery's tile does, which rounds it itself.
  final BoxFit fit;

  /// What shows in the image's place when it is not loaded or did not load, in place of its
  /// description.
  final WidgetBuilder? unloaded;

  /// The width in pixels a [BoxFit.cover] image is decoded at, keeping its proportions, so a
  /// small tile does not hold a large picture whole; null decodes it at its own size.
  final int? decodeWidth;

  /// Whether it may load: from the server's own host ([loadableImage]).
  bool get loadable => loadableImage(uri, server);

  @override
  State<AnswerImage> createState() => _AnswerImageState();
}

class _AnswerImageState extends State<AnswerImage> {
  /// The image's bytes as they are read, or null when it is not loaded or [_now] holds them.
  Future<Uint8List>? _bytes;

  /// The image's bytes when they were already read as it was built.
  Uint8List? _now;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(AnswerImage old) {
    super.didUpdateWidget(old);
    // An answer's images rebuild with each chunk of it, mostly unchanged.
    if (old.written != widget.written || old.server != widget.server) _read();
  }

  void _read() {
    final chat = AppScope.of(context).chat;
    final loadable = widget.loadable;
    _now = loadable ? chat.bytes.imageNow(widget.uri) : null;
    _bytes = loadable && _now == null ? chat.bytes.image(widget.uri) : null;
  }

  /// The tap on a description or a missing picture: it opens the image's address, unless the
  /// image is [AnswerImage.linked], where the link around it takes the tap and [why] is only
  /// its tooltip.
  Widget _tappable(
    BuildContext context,
    String name,
    String why,
    Widget child,
  ) {
    if (widget.linked) return Tooltip(message: why, child: child);
    return Tappable(
      label: 'Open $name',
      tooltip: why,
      onTap: () => openLink(context, widget.uri.toString()),
      child: child,
    );
  }

  /// An image that is not loaded, because it is not on the server's own host, drawn as a link
  /// to its host.
  Widget _described(BuildContext context, String name) {
    final t = Tokens.of(context);
    return _tappable(
      context,
      name,
      'Not loaded: images load only from the server\'s own host.',
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon('link', size: IconSize.xs, color: t.accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '[$name: ${widget.uri.host}]',
              style: Type.sans(
                14,
                color: t.accent,
              ).copyWith(decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
    );
  }

  /// What shows for an image that could be loaded and did not: a muted, outlined box with a
  /// picture mark and the description, so it reads as a picture that is missing rather than a
  /// link. It keeps the description's words, `[name: did not load]`, and says why in its
  /// tooltip.
  Widget _missing(BuildContext context, String name, {String? failure}) {
    final t = Tokens.of(context);
    final box = Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.panel2,
        borderRadius: BorderRadius.circular(Sizes.row + 2),
        border: Border.all(color: t.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          AppIcon('image', size: IconSize.normal, color: t.muted),
          Flexible(
            child: Text(
              '[$name: did not load]',
              style: Type.sans(13.5, color: t.muted, height: 1.35),
            ),
          ),
        ],
      ),
    );
    return _tappable(context, name, failure ?? 'The image did not load.', box);
  }

  Widget _unloaded(BuildContext context, {String? failure}) {
    if (widget.unloaded case final unloaded?) return unloaded(context);
    final alt = widget.alt?.trim();
    final name = alt != null && alt.isNotEmpty ? alt : 'image';
    return widget.loadable
        ? _missing(context, name, failure: failure)
        : _described(context, name);
  }

  /// The image drawn from [frame].
  Widget _image(BuildContext context, Uint8List frame) {
    Widget broken(BuildContext context, Object _, StackTrace? _) =>
        _unloaded(context);
    if (widget.fit != BoxFit.contain) {
      return Image.memory(
        frame,
        fit: widget.fit,
        cacheWidth: widget.decodeWidth,
        gaplessPlayback: true,
        semanticLabel: widget.alt,
        errorBuilder: broken,
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          frame,
          fit: BoxFit.contain,
          cacheHeight:
              (widget.maxHeight * MediaQuery.devicePixelRatioOf(context))
                  .round(),
          gaplessPlayback: true,
          semanticLabel: widget.alt,
          errorBuilder: broken,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    if (now != null) return _image(context, now);
    final bytes = _bytes;
    if (bytes == null) return _unloaded(context);
    return FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          return _unloaded(
            context,
            failure: error is ApiException ? error.message : '$error',
          );
        }
        final frame = snapshot.data;
        if (frame == null) return const SizedBox.shrink();
        return _image(context, frame);
      },
    );
  }
}
