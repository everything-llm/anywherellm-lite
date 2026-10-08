import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// An app's own page, in a web view inside its sheet on Android: [placeholder], the app's live
/// card, shows over it until the page's first load ends. The page may run its scripts, as its
/// ticks and adds need; a link off its host goes to [onLeave] instead.
Widget appWebView(
  Uri page, {
  required Widget placeholder,
  required void Function(Uri url) onLeave,
}) => _AppWebView(page: page, placeholder: placeholder, onLeave: onLeave);

class _AppWebView extends StatefulWidget {
  const _AppWebView({
    required this.page,
    required this.placeholder,
    required this.onLeave,
  });

  final Uri page;
  final Widget placeholder;
  final void Function(Uri url) onLeave;

  @override
  State<_AppWebView> createState() => _AppWebViewState();
}

class _AppWebViewState extends State<_AppWebView> {
  late final WebViewController _web;
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
            if (url != null && url.host == widget.page.host) {
              return NavigationDecision.navigate;
            }
            if (url != null) widget.onLeave(url);
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(widget.page);
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      WebViewWidget(controller: _web),
      if (!_loaded)
        ColoredBox(
          color: Theme.of(context).canvasColor,
          child: SingleChildScrollView(child: widget.placeholder),
        ),
    ],
  );
}
