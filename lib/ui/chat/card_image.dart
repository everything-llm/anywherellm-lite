import 'dart:async';
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
/// it takes the tap. A live
/// image, such as a run's progress card, shows each new frame as it comes, and is followed only
/// while it can be seen: not while the chat is offstage behind Files ([TickerMode]) or the app
/// is hidden, since a watched card keeps the host's browser from being stopped. Hiding is heard
/// here, not through [TickerMode], because a hidden app draws no frames to pass it down.
class CardImage extends StatefulWidget {
  const CardImage(
    this.uri, {
    super.key,
    required this.alt,
    required this.server,
    required this.allowHttp,
    required this.linked,
    this.maxHeight = 360,
  });

  final Uri uri;
  final String? alt;
  final Uri? server;
  final bool allowHttp;

  /// Whether the image sits inside a link, which then takes a tap on its description.
  final bool linked;

  /// The tallest it is drawn.
  final double maxHeight;

  bool get loadable => loadableImage(uri, server, allowHttp: allowHttp);

  @override
  State<CardImage> createState() => _CardImageState();
}

class _CardImageState extends State<CardImage> {
  Uint8List? _frame;

  /// Whether the read ended, by finishing or failing, so there is nothing more to follow.
  bool _ended = false;

  /// Why the read failed, or null.
  String? _failure;

  bool _onstage = true;
  bool _appShown = true;
  StreamSubscription<Uint8List>? _reading;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _reset();
    _lifecycle = AppLifecycleListener(
      onHide: () => _setAppShown(false),
      onShow: () => _setAppShown(true),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onstage = TickerMode.valuesOf(context).enabled;
    _follow();
  }

  @override
  void didUpdateWidget(CardImage old) {
    super.didUpdateWidget(old);
    if (old.uri == widget.uri && old.loadable == widget.loadable) return;
    _stop();
    _reset();
    _follow();
  }

  @override
  void dispose() {
    _stop();
    _lifecycle.dispose();
    super.dispose();
  }

  void _setAppShown(bool shown) {
    _appShown = shown;
    _follow();
  }

  /// Starts from the frame last read for this image, if any.
  void _reset() {
    _frame = widget.loadable
        ? AppScope.of(context).chat.lastFrame(widget.uri)
        : null;
    _ended = false;
    _failure = null;
  }

  /// Reads the image while it can be seen and has more to give, and lets go of it otherwise.
  void _follow() {
    if (!widget.loadable || !_onstage || !_appShown || _ended) {
      _stop();
      return;
    }
    _reading ??= AppScope.of(context).chat
        .imageFrames(widget.uri)
        .listen(
          _show,
          onError: (Object error) =>
              _end(failure: error is ApiException ? error.message : '$error'),
          onDone: _end,
          cancelOnError: true,
        );
  }

  /// Shows [frame] in place of the last, whose decoded image would otherwise stay in the image
  /// cache: each frame is its own [MemoryImage].
  void _show(Uint8List frame) {
    final last = _frame;
    if (last != null && !identical(last, frame)) {
      unawaited(MemoryImage(last).evict());
    }
    setState(() => _frame = frame);
  }

  /// Ends the read. One that failed after a frame keeps that frame and is read again the next
  /// time the image shows, since a live card's connection may only have dropped.
  void _end({String? failure}) => setState(() {
    _ended = failure == null || _frame == null;
    _failure = failure;
    _reading = null;
  });

  void _stop() {
    unawaited(_reading?.cancel());
    _reading = null;
  }

  /// The image's description, drawn as a link: the host it is not loaded from, or that it did
  /// not load, with why in its tooltip.
  Widget _described(BuildContext context) {
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
        ? _failure ?? 'The image did not load.'
        : 'Not loaded: images load only from the server\'s own host.';
    if (widget.linked) return Tooltip(message: why, child: text);
    return Tappable(
      label: 'Open $name',
      tooltip: why,
      onTap: () => openLink(context, widget.uri.toString()),
      child: text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    final described = _described(context);
    if (!widget.loadable || (frame == null && _ended)) return described;
    if (frame == null) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          frame,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          semanticLabel: widget.alt,
          errorBuilder: (_, _, _) => described,
        ),
      ),
    );
  }
}
