import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_scope.dart';

/// Apps' own pages in web views on Android. One page is kept loaded, the newest prefetched or
/// shown, so its sheet opens on the page at once; a page whose load failed is fetched again.
/// The page may run its scripts, as its ticks and adds need; while it shows, a link off its host
/// goes to the sheet's `onLeave` instead, and while it is out of sight nowhere.
class AppWebViews implements AppView {
  _AppPage? _kept;

  /// The page kept for [page], made afresh unless the one kept is [page] and has not failed.
  /// A kept page on screen is never replaced by a [prefetch].
  _AppPage? _keep(Uri page, {required bool showing}) {
    final kept = _kept;
    if (kept != null && kept.page == page && !kept.failed) return kept;
    if (kept != null && kept.shown > 0 && !showing) return null;
    kept?.drop();
    return _kept = _AppPage(page);
  }

  @override
  void prefetch(Uri page) => _keep(page, showing: false);

  @override
  Widget show(
    Uri page, {
    required Widget placeholder,
    required void Function(Uri url) onLeave,
  }) => _AppWebView(
    page: _keep(page, showing: true)!,
    placeholder: placeholder,
    onLeave: onLeave,
  );
}

/// [page] in a web view of its own, loading from the moment it is made.
class _AppPage extends ChangeNotifier {
  _AppPage(this.page) {
    web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (loaded) return;
            loaded = true;
            notifyListeners();
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) failed = true;
          },
          onNavigationRequest: (request) {
            final url = Uri.tryParse(request.url);
            if (url != null && url.host == page.host) {
              return NavigationDecision.navigate;
            }
            if (url != null) onLeave?.call(url);
            return NavigationDecision.prevent;
          },
        ),
      );
    unawaited(web.loadRequest(page));
  }

  final Uri page;
  late final WebViewController web;

  /// Whether the page's first load has ended, as it does when it fails too.
  bool loaded = false;

  /// Whether the page's own load failed, so it shows the web view's error and not the app.
  bool failed = false;

  /// How many sheets show the page now.
  int shown = 0;

  /// Where a link off the page's host goes while the page shows.
  void Function(Uri url)? onLeave;

  /// Empties the web view, so a page no longer kept holds no connection to its server.
  void drop() => unawaited(web.loadHtmlString(''));
}

class _AppWebView extends StatefulWidget {
  const _AppWebView({
    required this.page,
    required this.placeholder,
    required this.onLeave,
  });

  final _AppPage page;
  final Widget placeholder;
  final void Function(Uri url) onLeave;

  @override
  State<_AppWebView> createState() => _AppWebViewState();
}

class _AppWebViewState extends State<_AppWebView> {
  @override
  void initState() {
    super.initState();
    widget.page
      ..shown += 1
      ..onLeave = widget.onLeave;
  }

  @override
  void didUpdateWidget(_AppWebView old) {
    super.didUpdateWidget(old);
    if (identical(old.page, widget.page)) {
      widget.page.onLeave = widget.onLeave;
      return;
    }
    _leave(old.page);
    widget.page
      ..shown += 1
      ..onLeave = widget.onLeave;
  }

  @override
  void dispose() {
    _leave(widget.page);
    super.dispose();
  }

  static void _leave(_AppPage page) {
    page.shown -= 1;
    if (page.shown == 0) page.onLeave = null;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.page,
    builder: (context, _) => Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: widget.page.web),
        if (!widget.page.loaded)
          ColoredBox(
            color: Theme.of(context).canvasColor,
            child: SingleChildScrollView(child: widget.placeholder),
          ),
      ],
    ),
  );
}
