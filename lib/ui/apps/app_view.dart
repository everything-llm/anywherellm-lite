import 'package:flutter/widgets.dart';

/// Shows a page the app links to in the device's web view.
abstract interface class AppView {
  /// [page] in a web view that runs its scripts; a link off its host and port goes to
  /// [onLeave], the page closing itself (`window.close()`) to [onClose], and what the page
  /// posts to [channel] to it.
  Widget show(
    Uri page, {
    required void Function(Uri url) onLeave,
    VoidCallback? onClose,
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
