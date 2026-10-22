import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/skill_pages.dart';
import 'app_view.dart';

/// A page an answer links to in the device's web view. The page runs its scripts and stays on
/// its own origin; a link anywhere else goes to `onLeave` when the main frame follows it, and
/// `window.close()`, which a web view ignores, to `onClose`. A page the server answers with an
/// error, or cannot be reached, is covered by [PageGone] and tells `onFailed`. Only the page's own origin is given its channels, and only what
/// its main frame posts is heard, so a frame it embeds cannot speak as it. A page that holds a
/// secret ([holdsSecret]) is kept in the web view's cache only while it shows: the cache is
/// cleared before it loads and, with the page blanked so its scripts fetch nothing more, when it
/// closes, so one left by an app ended while it showed goes with the next such page.
class AppWebViews implements AppView {
  const AppWebViews();

  @override
  Widget show(
    Uri page, {
    required void Function(Uri url) onLeave,
    required VoidCallback onClose,
    VoidCallback? onFailed,
    PageChannel? channel,
  }) => _AppWebView(
    key: ValueKey(page),
    page: page,
    onLeave: onLeave,
    onClose: onClose,
    onFailed: onFailed,
    channel: channel,
  );
}

/// The channel a page's `window.close()` calls to close what shows it.
const _closeChannel = 'AnywhereLLMClose';

/// How a page's channels reach the app: `PageChannels` (`android/.../PageChannels.kt`) gives a
/// web view's frames of one origin each channel, and hands back what the main frame posts.
final _pages = const MethodChannel('anywherellm/pages')
  ..setMethodCallHandler((call) async {
    if (call.arguments case {
      'view': final int view,
      'name': final String name,
      'message': final String message,
    }) {
      _heard[(view, name)]?.call(message);
    }
  });

/// What each web view's main frame posts to a channel goes to, by the web view and the name.
final _heard = <(int, String), void Function(String message)>{};

/// Asks `PageChannels` to do [method] to web view [view] through the app's own channel, since
/// the plugin answers no call on a web view whose widget has gone: `forget` blanks it and empties
/// the HTTP cache the app's web views share, and `edgeless` keeps the window's insets from it,
/// since it shows in a sheet clear of the system bars. A failure leaves it as it was: the cache is
/// emptied again before the next page that holds a secret loads, and a page leaves room for bars
/// it is not under.
Future<void> _tell(String method, int view) async {
  try {
    await _pages.invokeMethod<void>(method, {'view': view});
  } on PlatformException {
    // As above.
  }
}

/// Asks `PageChannels` to give web view [view]'s frames of [page]'s origin a channel of each of
/// [names]; false where the device's web view cannot, and the page then has none.
Future<bool> _listen(int view, Uri page, Iterable<String> names) async {
  try {
    return await _pages.invokeMethod<bool>('listen', {
          'view': view,
          'names': [...names],
          'origin': page.origin,
        }) ??
        false;
  } on PlatformException {
    return false;
  }
}

class _AppWebView extends StatefulWidget {
  const _AppWebView({
    super.key,
    required this.page,
    required this.onLeave,
    required this.onClose,
    this.onFailed,
    this.channel,
  });

  final Uri page;
  final void Function(Uri url) onLeave;
  final VoidCallback onClose;
  final VoidCallback? onFailed;
  final PageChannel? channel;

  @override
  State<_AppWebView> createState() => _AppWebViewState();
}

class _AppWebViewState extends State<_AppWebView> {
  late final WebViewController _web;

  /// Whether the page's first load has ended, as it does when it fails too.
  bool _loaded = false;

  /// Whether the page itself failed to load, which [PageGone] says.
  bool _gone = false;

  /// The web view's id at `PageChannels`, once its channels are asked for.
  int? _view;

  /// Whether the web view shows, or has shown, a page that holds a secret ([holdsSecret]), so its
  /// cache is cleared when it closes: the page it opened on, or one it moved to in place.
  late bool _private = holdsSecret(widget.page);

  @override
  void initState() {
    super.initState();
    final page = widget.page;
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            unawaited(
              _web.runJavaScript(
                "if(window.$_closeChannel)window.close=()=>$_closeChannel.postMessage('close')",
              ),
            );
            if (mounted && !_loaded) setState(() => _loaded = true);
          },
          onHttpError: (error) {
            if (pageFailed(
              page,
              error.request?.uri,
              error.response?.statusCode,
            )) {
              _fail();
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? false) _fail();
          },
          onNavigationRequest: (request) {
            final url = Uri.tryParse(request.url);
            if (url == null) return NavigationDecision.prevent;
            switch (offOriginMove(page, url, request.isMainFrame)) {
              case PageMove.stay:
                if (request.isMainFrame && holdsSecret(url)) _private = true;
                return NavigationDecision.navigate;
              case PageMove.leave:
                widget.onLeave(url);
              case PageMove.block:
            }
            return NavigationDecision.prevent;
          },
        ),
      );
    if (_web.platform case final AndroidWebViewController android) {
      _view = android.webViewIdentifier;
    }
    unawaited(_open());
  }

  /// Covers the page with [PageGone], once, and tells the sheet that shows it.
  void _fail() {
    if (!mounted || _gone) return;
    setState(() => _gone = true);
    widget.onFailed?.call();
  }

  /// Gives the page its channels, which must come before it loads to reach its first document,
  /// then loads it.
  Future<void> _open() async {
    final page = widget.page;
    if (_view case final view?) {
      await _tell('edgeless', view);
      if (!mounted) return;
      final heard = <String, void Function(String message)>{
        _closeChannel: (_) => widget.onClose(),
        if (widget.channel case final channel?) channel.name: channel.onMessage,
      };
      if (await _listen(view, page, heard.keys)) {
        if (!mounted) return;
        heard.forEach((name, onMessage) => _heard[(view, name)] = onMessage);
      }
    }
    if (!mounted) return;
    if (_private) {
      await _web.clearCache();
      if (!mounted) return;
    }
    widget.channel?.runner = _web.runJavaScript;
    await _web.loadRequest(page);
  }

  @override
  void dispose() {
    if (_view case final view?) {
      _heard.removeWhere((key, _) => key.$1 == view);
    }
    // A web view that took its place may have set its own runner already.
    if (widget.channel case final channel?
        when channel.runner == _web.runJavaScript) {
      channel.runner = null;
    }
    if (_private) {
      if (_view case final view?) unawaited(_tell('forget', view));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      // The page takes every touch on it at once. Without this the app's SelectionArea joins
      // each gesture's arena: the page then gets a scroll only after the selection's drag gives
      // up, a sideways drag or a hold never, and nothing while the arena is undecided.
      WebViewWidget(
        controller: _web,
        gestureRecognizers: {Factory(EagerGestureRecognizer.new)},
      ),
      if (!_loaded)
        ColoredBox(
          color: Theme.of(context).canvasColor,
          child: const Center(child: CircularProgressIndicator()),
        ),
      if (_gone) PageGone(onClose: widget.onClose),
    ],
  );
}
