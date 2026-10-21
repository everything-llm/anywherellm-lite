import 'package:flutter/widgets.dart';

import 'app_scope.dart';
import 'state/shell_controller.dart';
import 'widgets/sheet.dart';

/// [child], with a popup over the whole window while the shell's popup
/// ([ShellController.popup]) is this one's: [ShellPopup.new]'s key itself, or, with
/// [ShellPopup.any], any popup that is a [K]. It shows what its builder builds in a [ModalSheet]
/// under its title, as a [PopupSheet] does, or, with no title, as it is, as an image over the
/// window. Esc, the scrim, Close and a drag down close it, as does the `close` its builder is
/// handed, and each closes only the popup this one shows, never another opened meanwhile.
///
/// It closes its popup after the frame, and hides it at once: when what the popup is about is
/// gone (`present`), when its [subject] changes, when it no longer opens that popup, and when it
/// leaves the tree with it open, as with the answer it belongs to, so Back has nothing hidden
/// to close.
class ShellPopup<K extends Object> extends StatefulWidget {
  /// Opens while the shell's popup is [popup], until [present] is false.
  ShellPopup({
    super.key,
    required K this._popup,
    String? title,
    bool present = true,
    this.subject,
    required Widget Function(BuildContext context, VoidCallback close) builder,
    required this.child,
  }) : _title = title == null ? null : ((_) => title),
       _present = ((_) => present),
       _builder = ((context, _, close) => builder(context, close));

  /// Opens while the shell's popup is any [K], which [title], [present] and [builder] are handed,
  /// until [present] says what it is about is gone.
  ShellPopup.any({
    super.key,
    required String Function(K open) this._title,
    bool Function(K open)? present,
    this.subject,
    required this._builder,
    required this.child,
  }) : _popup = null,
       _present = present ?? ((_) => true);

  /// The popup it opens on, or null for any [K].
  final K? _popup;
  final String Function(K open)? _title;
  final bool Function(K open) _present;
  final Widget Function(BuildContext context, K open, VoidCallback close)
  _builder;

  /// What the popup is about, such as the workspace open: another closes it.
  final Object? subject;

  final Widget child;

  @override
  State<ShellPopup<K>> createState() => _ShellPopupState<K>();
}

class _ShellPopupState<K extends Object> extends State<ShellPopup<K>> {
  late final ShellController _shell = AppScope.of(context).shell;

  /// The popup that closes after this frame, hidden meanwhile.
  K? _going;

  @override
  void initState() {
    super.initState();
    _shell.popup.addListener(_popupChanged);
    _closeIfGone();
  }

  @override
  void didUpdateWidget(ShellPopup<K> old) {
    super.didUpdateWidget(old);
    final open = _openFor(old);
    if (open != null &&
        (!identical(_openFor(widget), open) || widget.subject != old.subject)) {
      _closeAfterFrame(open);
    } else {
      _closeIfGone();
    }
  }

  @override
  void dispose() {
    _shell.popup.removeListener(_popupChanged);
    if (_openFor(widget) case final open?) _closeAfterFrame(open);
    super.dispose();
  }

  void _popupChanged() {
    setState(() {});
    _closeIfGone();
  }

  /// The shell's popup when [popup] opens on it, or null.
  K? _openFor(ShellPopup<K> popup) => switch (_shell.popup.value) {
    final K open when popup._popup == null || identical(open, popup._popup) =>
      open,
    _ => null,
  };

  void _closeIfGone() {
    if (_openFor(widget) case final open? when !widget._present(open)) {
      _closeAfterFrame(open);
    }
  }

  /// Closes [open] once the frame being built, or torn down, is done.
  void _closeAfterFrame(K open) {
    _going = open;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shell.closePopup(open);
      if (identical(_going, open)) _going = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final open = _openFor(widget);
    return OverlayWhile(
      open: open != null && !identical(open, _going) && widget._present(open),
      overlay: (context) => _overlay(context, open!),
      child: widget.child,
    );
  }

  Widget _overlay(BuildContext context, K open) {
    void close() => _shell.closePopup(open);
    final body = Builder(
      builder: (context) => widget._builder(context, open, close),
    );
    return switch (widget._title) {
      final title? => ModalSheet(
        title: title(open),
        onClose: close,
        child: body,
      ),
      null => body,
    };
  }
}
