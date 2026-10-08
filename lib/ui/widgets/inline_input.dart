import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';
import '../type.dart';

/// A small text field that takes Enter to commit and Esc to cancel.
class InlineInput extends StatefulWidget {
  const InlineInput({
    super.key,
    required this.controller,
    required this.label,
    required this.height,
    required this.onSubmit,
    required this.onCancel,
    this.hint,
    this.maxLength,
    this.commitOnBlur = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final double height;
  final int? maxLength;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  /// Commits when focus leaves, as a rename does. Otherwise leaving cancels.
  final bool commitOnBlur;

  @override
  State<InlineInput> createState() => _InlineInputState();
}

class _InlineInputState extends State<InlineInput> {
  final _focus = FocusNode();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // autofocus yields to the shell's own focus, so ask outright once laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    _focus.addListener(() {
      if (_focus.hasFocus || _done) return;
      _finish(widget.commitOnBlur ? widget.onSubmit : widget.onCancel);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Runs [then] once, whether Enter, Esc or a lost focus came first.
  void _finish(VoidCallback then) {
    if (_done) return;
    _done = true;
    then();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(widget.height > 30 ? 8 : 6),
      borderSide: BorderSide(color: t.accent),
    );
    return SizedBox(
      height: widget.height,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _finish(widget.onCancel),
          // A soft keyboard's Done sends a text action, not a key, which onEditingComplete
          // takes; [_finish] runs once whichever comes first.
          const SingleActivator(LogicalKeyboardKey.enter): () =>
              _finish(widget.onSubmit),
          const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
              _finish(widget.onSubmit),
        },
        child: Semantics(
          label: widget.label,
          textField: true,
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            onEditingComplete: () => _finish(widget.onSubmit),
            maxLength: widget.maxLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            style: Type.sans(13.5, color: t.ink),
            cursorColor: t.accent,
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              filled: true,
              fillColor: t.panel,
              hintText: widget.hint,
              hintStyle: Type.sans(13.5, color: t.fade),
              semanticCounterText: '',
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              border: border,
              enabledBorder: border,
              focusedBorder: border,
            ),
          ),
        ),
      ),
    );
  }
}
