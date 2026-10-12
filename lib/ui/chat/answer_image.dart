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

/// An image in an answer: loaded when it is on the [server]'s host over https, or over http
/// when the [server] itself is http and [allowHttp] holds; otherwise its description. The
/// description says whether the image was not loaded or failed to load, and why it failed. It
/// opens the image's address when tapped, unless the image is [linked], where the link around
/// it takes the tap.
class AnswerImage extends StatefulWidget {
  const AnswerImage(
    this.uri, {
    super.key,
    required this.alt,
    required this.server,
    required this.allowHttp,
    required this.linked,
    this.maxHeight = 360,
    this.fit = BoxFit.contain,
    this.unloaded,
    this.decodeWidth,
  });

  final Uri uri;
  final String? alt;
  final Uri? server;
  final bool allowHttp;

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

  bool get loadable => loadableImage(uri, server, allowHttp: allowHttp);

  @override
  State<AnswerImage> createState() => _AnswerImageState();
}

class _AnswerImageState extends State<AnswerImage> {
  /// The image's bytes as they are read, or null when it is not loaded.
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(AnswerImage old) {
    super.didUpdateWidget(old);
    // An answer's images rebuild with each chunk of it, mostly unchanged.
    if (old.uri != widget.uri || old.loadable != widget.loadable) _read();
  }

  void _read() => _bytes = widget.loadable
      ? AppScope.of(context).chat.imageBytes(widget.uri)
      : null;

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

  @override
  Widget build(BuildContext context) {
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
              gaplessPlayback: true,
              semanticLabel: widget.alt,
              errorBuilder: broken,
            ),
          ),
        );
      },
    );
  }
}
