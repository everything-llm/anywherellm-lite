import 'package:flutter/material.dart';

import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';

/// Shows a page the app links to in the device's web view.
abstract interface class AppView {
  /// [page] in a web view that runs its scripts; a link off its origin goes to
  /// [onLeave], the page closing itself (`window.close()`) to [onClose], and what the page
  /// posts to [channel] to it. A page that fails to load, such as one the server no longer has,
  /// is covered by [PageGone] and tells [onFailed].
  Widget show(
    Uri page, {
    required void Function(Uri url) onLeave,
    VoidCallback? onClose,
    VoidCallback? onFailed,
    PageChannel? channel,
  });
}

/// What a page in an [AppView] and the app say to each other: the page posts to
/// `window.<name>.postMessage`, which [onMessage] hears, and the app runs script in the page
/// through [run].
class PageChannel {
  PageChannel(this.name, this.onMessage);

  final String name;
  final void Function(String message) onMessage;

  /// Runs script in the page, set by the web view that shows it.
  Future<void> Function(String script)? runner;

  /// Runs [script] in the page, or nothing while no page shows.
  Future<void> run(String script) async => runner?.call(script);
}

/// Whether a response to [url] with HTTP [status] is the page [page] itself failing: an error
/// status for its own address, query aside. A picture or script it loads that fails does not
/// count.
bool pageFailed(Uri page, Uri? url, int? status) =>
    url != null &&
    status != null &&
    status >= 400 &&
    url.scheme == page.scheme &&
    url.host == page.host &&
    url.port == page.port &&
    url.path == page.path;

/// What a web view does with a move to an address: [stay] on the page's origin, [leave] it for
/// the browser, or [block] it without a word.
enum PageMove { stay, leave, block }

/// What to do with a move to [url] from [page], made by the main frame or, when [mainFrame] is
/// false, by a frame in it. Only the main frame reaches the browser, since a frame or a script
/// can move with no tap.
PageMove offOriginMove(Uri page, Uri url, bool mainFrame) {
  if (url.scheme == page.scheme &&
      url.host == page.host &&
      url.port == page.port) {
    return PageMove.stay;
  }
  return mainFrame ? PageMove.leave : PageMove.block;
}

/// Over a page that failed to load: links in older answers can stop working, since the server
/// rotates a page's address, so it says so over the page rather than leave the server's own
/// error showing.
class PageGone extends StatelessWidget {
  const PageGone({super.key, required this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ColoredBox(
      color: t.bg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Text(
                'This page is gone',
                textAlign: TextAlign.center,
                style: Type.sans(20, weight: FontWeight.w600, color: t.ink),
              ),
              Text(
                'Links in older answers can stop working. Ask the agent for the page again.',
                textAlign: TextAlign.center,
                style: Type.sans(15, color: t.muted, height: 1.45),
              ),
              if (onClose != null) ...[
                const SizedBox(height: 8),
                AppButton('Close', onPressed: onClose),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
