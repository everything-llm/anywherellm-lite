import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_screen.dart';

/// An app's working page in the device's web view. The page runs its scripts, as its ticks and
/// adds need, and stays on its own host and port; a link anywhere else goes to `onLeave`, and
/// `window.close()`, which a web view ignores, to `onClose`.
class AppWebViews implements AppView {
  const AppWebViews();

  @override
  Widget show(
    Uri page, {
    required void Function(Uri url) onLeave,
    VoidCallback? onClose,
  }) => _AppWebView(
    key: ValueKey(page),
    page: page,
    onLeave: onLeave,
    onClose: onClose,
  );
}

/// The channel a page's `window.close()` calls to close what shows it.
const _closeChannel = 'AnywhereLLMClose';

class _AppWebView extends StatefulWidget {
  const _AppWebView({
    super.key,
    required this.page,
    required this.onLeave,
    this.onClose,
  });

  final Uri page;
  final void Function(Uri url) onLeave;
  final VoidCallback? onClose;

  @override
  State<_AppWebView> createState() => _AppWebViewState();
}

class _AppWebViewState extends State<_AppWebView> {
  late final WebViewController _web;

  /// Whether the page's first load has ended, as it does when it fails too.
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (widget.onClose != null) {
              unawaited(
                _web.runJavaScript(
                  "window.close=()=>$_closeChannel.postMessage('close')",
                ),
              );
            }
            if (mounted && !_loaded) setState(() => _loaded = true);
          },
          onNavigationRequest: (request) {
            final url = Uri.tryParse(request.url);
            if (url != null &&
                url.host == widget.page.host &&
                url.port == widget.page.port) {
              return NavigationDecision.navigate;
            }
            if (url != null) widget.onLeave(url);
            return NavigationDecision.prevent;
          },
        ),
      );
    if (widget.onClose case final close?) {
      unawaited(
        _web.addJavaScriptChannel(
          _closeChannel,
          onMessageReceived: (_) => close(),
        ),
      );
    }
    unawaited(_web.loadRequest(widget.page));
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
