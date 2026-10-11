import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_scope.dart';

/// The everythingllm browser's take-over view in a web view on Android, with the channel the
/// page looks for, `AnywhereLLM`: it then draws Back and its message bar, and posts
/// `{"back": true}` or `{"say": text}` to it. The line `onSay` answers goes back to the page
/// through `window.anywhereLLM.said`. The view stays on its own port; a login request's form
/// and any other address go to `onLeave`, so the screen stays the view.
class TakeoverWebView implements TakeoverView {
  const TakeoverWebView();

  @override
  Widget show(
    Uri page, {
    required Widget placeholder,
    required VoidCallback onBack,
    required Future<String> Function(String text) onSay,
    required void Function(Uri url) onLeave,
  }) => _TakeoverWebView(
    key: ValueKey(page),
    page: page,
    placeholder: placeholder,
    onBack: onBack,
    onSay: onSay,
    onLeave: onLeave,
  );
}

class _TakeoverWebView extends StatefulWidget {
  const _TakeoverWebView({
    super.key,
    required this.page,
    required this.placeholder,
    required this.onBack,
    required this.onSay,
    required this.onLeave,
  });

  final Uri page;
  final Widget placeholder;
  final VoidCallback onBack;
  final Future<String> Function(String text) onSay;
  final void Function(Uri url) onLeave;

  @override
  State<_TakeoverWebView> createState() => _TakeoverWebViewState();
}

class _TakeoverWebViewState extends State<_TakeoverWebView> {
  late final WebViewController _web;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'AnywhereLLM',
        onMessageReceived: (message) => unawaited(_heard(message.message)),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted && !_loaded) setState(() => _loaded = true);
          },
          onNavigationRequest: (request) {
            final url = Uri.tryParse(request.url);
            if (url != null && _stays(url)) return NavigationDecision.navigate;
            if (url != null) widget.onLeave(url);
            return NavigationDecision.prevent;
          },
        ),
      );
    unawaited(_web.loadRequest(widget.page));
  }

  /// Whether [url] is the view itself: on the page's host and port, or anywhere on its host
  /// when the page is a card's link, which redirects to the view's own port. A login request's
  /// form is a page of its own.
  bool _stays(Uri url) {
    final page = widget.page;
    if (url.host != page.host || url.path.startsWith('/login/')) return false;
    return url.port == page.port || page.path.startsWith('/_live/browser/');
  }

  /// What the page posted: Back, or a message for the chat, whose answer it shows.
  Future<void> _heard(String message) async {
    final Object? said;
    try {
      said = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (said is! Map) return;
    if (said['back'] == true) {
      widget.onBack();
      return;
    }
    if (said['say'] case final String text when text.trim().isNotEmpty) {
      final line = await widget.onSay(text.trim());
      if (!mounted) return;
      await _web.runJavaScript(
        'window.anywhereLLM && window.anywhereLLM.said(${jsonEncode(line)});',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      WebViewWidget(controller: _web),
      if (!_loaded)
        ColoredBox(
          color: Theme.of(context).canvasColor,
          child: widget.placeholder,
        ),
    ],
  );
}
