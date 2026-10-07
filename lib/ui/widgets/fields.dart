import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';

/// The input: one line 44px tall, or [maxLines] lines, rounded, a ring in the accent on focus.
class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.onChanged,
    this.onSubmitted,
    this.icon,
    this.suffix,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.maxLines = 1,
  });

  final TextEditingController controller;

  /// The accessible name. The field has no visible label of its own.
  final String label;
  final String? hint;

  /// Called on an edit by the person, not when the controller's text is set in code.
  final ValueChanged<String>? onChanged;

  /// Called when the person presses Enter.
  final ValueChanged<String>? onSubmitted;

  /// The name of an icon drawn inside the field, before the text.
  final String? icon;

  /// A widget drawn inside the field, after the text.
  final Widget? suffix;

  /// Hides the text, as for a key. It also keeps the keyboard from learning it.
  final bool obscure;

  final TextInputType? keyboardType;

  /// What the system may fill in, such as a web address. Null, the default, leaves the field
  /// out of autofill, so a key is never offered a saved password.
  final Iterable<String>? autofillHints;

  /// More than 1 makes a box of text that starts 3 lines tall and grows to this many.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(Sizes.control),
          borderSide: BorderSide(color: color, width: width),
        );
    return Semantics(
      label: label,
      textField: true,
      child: TextField(
        controller: controller,
        autocorrect: false,
        // Flutter on Android marks a field without suggestions as a visible password, which
        // would replace a web-address or multiline keyboard and invite a saved login. A URL
        // keyboard offers no word suggestions anyway.
        enableSuggestions: keyboardType == TextInputType.url || maxLines > 1,
        obscureText: obscure,
        keyboardType:
            keyboardType ?? (maxLines > 1 ? TextInputType.multiline : null),
        minLines: maxLines > 1 ? 3 : null,
        maxLines: maxLines,
        autofillHints: autofillHints,
        enableIMEPersonalizedLearning: !obscure,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: Type.sans(15).copyWith(color: t.ink),
        cursorColor: t.accent,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: t.bg,
          hintText: hint,
          hintStyle: Type.sans(15, color: t.fade),
          prefixIcon: icon == null
              ? null
              : Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14, right: 8),
                    child: AppIcon(icon!, size: IconSize.sm, color: t.muted),
                  ),
                ),
          suffixIcon: suffix == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: suffix,
                ),
          prefixIconConstraints: const BoxConstraints(minHeight: 44),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 13,
          ),
          constraints: const BoxConstraints(minHeight: 44),
          enabledBorder: border(t.line),
          focusedBorder: border(t.accent, 2),
        ),
      ),
    );
  }
}

/// A line of small muted text. [status] makes a screen reader announce it when it changes.
class HelpText extends StatelessWidget {
  const HelpText(this.text, {super.key, this.status = false});

  final String text;
  final bool status;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final body = Text(
      text,
      style: Type.sans(12.5, color: t.muted, height: 1.45),
    );
    return status ? Semantics(liveRegion: true, child: body) : body;
  }
}
