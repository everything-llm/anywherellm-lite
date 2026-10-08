import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'basics.dart';
import 'buttons.dart';

/// A warning that asks once more before something is deleted, with Cancel and [action]. Esc
/// cancels.
class ConfirmBox extends StatefulWidget {
  const ConfirmBox({
    super.key,
    required this.text,
    required this.onCancel,
    required this.onConfirm,
    this.action = 'Delete',
  });

  final String text;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String action;

  @override
  State<ConfirmBox> createState() => _ConfirmBoxState();
}

class _ConfirmBoxState extends State<ConfirmBox> {
  final _focus = FocusNode(debugLabel: 'ConfirmBox');

  @override
  void initState() {
    super.initState();
    // Takes the focus from wherever it was, such as the composer, so Esc reaches it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
    },
    child: Focus(
      focusNode: _focus,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AlertBox(AlertKind.warn, widget.text, plain: true),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton('Cancel', onPressed: widget.onCancel),
              AppButton(
                widget.action,
                primary: true,
                onPressed: widget.onConfirm,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
