import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../tokens.dart';
import '../type.dart';

/// The chat's browser tab as the server shows it now, one picture read again every second while
/// it can be seen, never while the chat is offstage behind Files ([TickerMode]) or the app is
/// hidden, since reading it counts as watching the tab, which keeps the host's browser from
/// being stopped. A picture that has not changed is not drawn again. It is read through the
/// developer key, so a browser build can draw it too, which the tab's own card does not allow.
class BrowserFrame extends StatefulWidget {
  const BrowserFrame({super.key});

  @override
  State<BrowserFrame> createState() => _BrowserFrameState();
}

class _BrowserFrameState extends State<BrowserFrame> {
  static const _every = Duration(seconds: 1);
  static const _tallest = 520.0;

  Uint8List? _bytes;
  String? _etag;

  /// Whether a read has finished, so a missing picture is one the server has not got.
  bool _asked = false;

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
        _timer = Timer.periodic(_every, (_) => unawaited(_read()));
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
        setState(() {
          _bytes = null;
          _etag = null;
          _asked = true;
        });
      } else if (got.bytes case final bytes?) {
        // Each picture is its own [MemoryImage], so the last is let go of.
        if (_bytes case final last?) unawaited(MemoryImage(last).evict());
        setState(() {
          _bytes = bytes;
          _etag = got.etag;
          _asked = true;
        });
      }
    } finally {
      _reading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    Widget note(String text) => AspectRatio(
      aspectRatio: 16 / 9,
      child: Center(
        child: Text(text, style: Type.sans(13, color: t.muted)),
      ),
    );
    final bytes = _bytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.hover,
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: bytes == null
            ? note(
                _asked
                    ? 'The browser has no picture now.'
                    : 'Reading the browser…',
              )
            : Semantics(
                label: 'The browser, as it looks now',
                image: true,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _tallest),
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    width: double.infinity,
                    // A picture that cannot be read is no picture; the next one may be.
                    errorBuilder: (context, error, stack) =>
                        note('The browser\'s picture could not be shown.'),
                  ),
                ),
              ),
      ),
    );
  }
}
