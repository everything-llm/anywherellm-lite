import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../tokens.dart';
import '../type.dart';

/// The chat's browser tab as the server shows it now, one picture read again every [every]
/// while it can be seen, never while the chat is offstage behind Files ([TickerMode]) or the
/// app is hidden, since reading it counts as watching the tab, which keeps the host's browser
/// from being stopped. A picture that has not changed is not drawn again. It is read through
/// the developer key, so a browser build can draw it too, which the tab's own card does not
/// allow.
class BrowserFrame extends StatefulWidget {
  const BrowserFrame({
    super.key,
    this.every = const Duration(seconds: 1),
    this.maxHeight = 520,
  });

  final Duration every;

  /// The tallest it is drawn.
  final double maxHeight;

  @override
  State<BrowserFrame> createState() => _BrowserFrameState();
}

class _BrowserFrameState extends State<BrowserFrame> {
  Uint8List? _bytes;
  String? _etag;

  /// Whether the last read found no picture, as when the tab closed.
  bool _gone = false;

  Timer? _timer;
  bool _reading = false;
  bool _onstage = true;
  bool _appShown = true;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
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
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _setAppShown(bool shown) {
    _appShown = shown;
    _follow();
  }

  /// Reads the picture while it can be seen, and stops otherwise.
  void _follow() {
    if (_onstage && _appShown) {
      if (_timer == null) {
        _timer = Timer.periodic(widget.every, (_) => unawaited(_read()));
        unawaited(_read());
      }
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _read() async {
    if (_reading) return;
    _reading = true;
    try {
      final got = await AppScope.of(context).browser.frame(etag: _etag);
      if (!mounted) return;
      if (got == null) {
        if (!_gone) setState(() => _gone = true);
      } else if (got.bytes case final bytes?) {
        // Each picture is its own [MemoryImage], so the last is let go of.
        if (_bytes case final last?) unawaited(MemoryImage(last).evict());
        setState(() {
          _bytes = bytes;
          _etag = got.etag;
          _gone = false;
        });
      } else if (_gone) {
        setState(() => _gone = false);
      }
    } finally {
      _reading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final bytes = _bytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.hover,
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: bytes == null || _gone
            ? AspectRatio(
                aspectRatio: 16 / 9,
                child: Center(
                  child: Text(
                    _gone
                        ? 'The browser has no picture now.'
                        : 'Reading the browser…',
                    style: Type.sans(13, color: t.muted),
                  ),
                ),
              )
            : Semantics(
                label: 'The browser, as it looks now',
                image: true,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: widget.maxHeight),
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    width: double.infinity,
                    // A picture that cannot be read is no picture; the next one may be.
                    errorBuilder: (context, error, stack) => AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Center(
                        child: Text(
                          'The browser\'s picture could not be shown.',
                          style: Type.sans(13, color: t.muted),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
