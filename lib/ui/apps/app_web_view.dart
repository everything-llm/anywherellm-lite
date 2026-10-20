import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'app_view.dart';

/// A page an answer links to in the device's web view. The page runs its scripts and stays on
/// its own origin; a link anywhere else goes to `onLeave`, and `window.close()`, which a web
/// view ignores, to `onClose`. Only the page's own origin is given its channels, and only what
/// its main frame posts is heard, so a frame it embeds cannot speak as it.
class AppWebViews implements AppView {
  const AppWebViews();

  @override
  Widget show(
    Uri page, {
    required void Function(Uri url) onLeave,
    VoidCallback? onClose,
    PageChannel? channel,
  }) => _AppWebView(
    key: ValueKey(page),
    page: page,
    onLeave: onLeave,
    onClose: onClose,
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
    this.onClose,
    this.channel,
  });

  final Uri page;
  final void Function(Uri url) onLeave;
  final VoidCallback? onClose;
  final PageChannel? channel;

  @override
  State<_AppWebView> createState() => _AppWebViewState();
}

class _AppWebViewState extends State<_AppWebView> {
  late final WebViewController _web;

  /// Whether the page's first load has ended, as it does when it fails too.
  bool _loaded = false;

  /// The web view's id at `PageChannels`, once its channels are asked for.
  int? _view;

  @override
  void initState() {
    super.initState();
    final page = widget.page;
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (widget.onClose != null) {
              unawaited(
                _web.runJavaScript(
                  "if(window.$_closeChannel)window.close=()=>$_closeChannel.postMessage('close')",
                ),
              );
            }
            if (mounted && !_loaded) setState(() => _loaded = true);
          },
          onNavigationRequest: (request) {
            final url = Uri.tryParse(request.url);
            if (url != null &&
                url.scheme == page.scheme &&
                url.host == page.host &&
                url.port == page.port) {
              return NavigationDecision.navigate;
            }
            if (url != null) widget.onLeave(url);
            return NavigationDecision.prevent;
          },
        ),
      );
    if (_web.platform case final AndroidWebViewController android) {
      _view = android.webViewIdentifier;
    }
    unawaited(_open());
  }

  /// Gives the page its channels, which must come before it loads to reach its first document,
  /// then loads it.
  Future<void> _open() async {
    final page = widget.page;
    if (_view case final view?) {
      final heard = <String, void Function(String message)>{
        if (widget.onClose case final close?) _closeChannel: (_) => close(),
        if (widget.channel case final channel?) channel.name: channel.onMessage,
      };
      if (heard.isNotEmpty && await _listen(view, page, heard.keys)) {
        if (!mounted) return;
        heard.forEach((name, onMessage) => _heard[(view, name)] = onMessage);
      }
    }
    if (!mounted) return;
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
    ],
  );
}
