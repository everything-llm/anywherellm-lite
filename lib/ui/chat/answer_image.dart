import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../../core/ports.dart';
import '../app_scope.dart';
import '../icons.dart';
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
    _now = loadable ? chat.imageNow(widget.uri) : null;
    _bytes = loadable && _now == null ? chat.imageBytes(widget.uri) : null;
  }

  /// The image's description, drawn as a link: the host it is not loaded from, or that it did
  /// not load, with [failure] in its tooltip.
  Widget _described(BuildContext context, {String? failure}) {
    final t = Tokens.of(context);
    final alt = widget.alt?.trim();
    final name = alt != null && alt.isNotEmpty ? alt : 'image';
    final failed = widget.loadable;
    final text = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon('link', size: IconSize.xs, color: t.accent),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '[$name: ${failed ? 'did not load' : widget.uri.host}]',
            style: Type.sans(
              14,
              color: t.accent,
            ).copyWith(decoration: TextDecoration.underline),
          ),
        ),
      ],
    );
    final why = failed
        ? failure ?? 'The image did not load.'
        : 'Not loaded: images load only from the server\'s own host.';
    if (widget.linked) return Tooltip(message: why, child: text);
    return Tappable(
      label: 'Open $name',
      tooltip: why,
      onTap: () => openLink(context, widget.uri.toString()),
      child: text,
    );
  }

  Widget _unloaded(BuildContext context, {String? failure}) =>
      widget.unloaded?.call(context) ?? _described(context, failure: failure);

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
