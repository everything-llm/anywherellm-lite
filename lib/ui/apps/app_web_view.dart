import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_screen.dart';

/// An app's working page in the device's web view. The page runs its scripts, as its ticks and
/// adds need, and stays on its own host and port; a link anywhere else goes to `onLeave`.
class AppWebViews implements AppView {
  const AppWebViews();

  @override
  Widget show(Uri page, {required void Function(Uri url) onLeave}) =>
      _AppWebView(key: ValueKey(page), page: page, onLeave: onLeave);
}

class _AppWebView extends StatefulWidget {
  const _AppWebView({super.key, required this.page, required this.onLeave});

  final Uri page;
  final void Function(Uri url) onLeave;

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
    unawaited(_web.loadRequest(widget.page));
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      WebViewWidget(controller: _web),
      if (!_loaded)
        ColoredBox(
          color: Theme.of(context).canvasColor,
          child: const Center(child: CircularProgressIndicator()),
        ),
    ],
  );
}
