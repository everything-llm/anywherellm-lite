import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// A text field's outline.
Color fieldEdge(BuildContext context) => Tokens.of(context).edge;

/// A text field's fill.
Color fieldFill(BuildContext context) => Tokens.of(context).bg;

/// The look of a text area that fills its space, such as the prompt editor: [fill] behind it,
/// [fieldEdge] round it, and the accent, 2 px, while it has the focus. [padding] is round the
/// text, 14 on every side unless given.
InputDecoration editorDecoration(
  BuildContext context,
  Color fill, {
  EdgeInsets? padding,
}) {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Sizes.control),
    borderSide: BorderSide(color: color, width: width),
  );
  return InputDecoration(
    filled: true,
    fillColor: fill,
    contentPadding: padding ?? const EdgeInsets.all(14),
    enabledBorder: border(fieldEdge(context), 1),
    focusedBorder: border(Tokens.of(context).accent, 2),
  );
}

/// The input: one line 52px tall, or [maxLines] lines, rounded, a ring in the
/// accent on focus.
class AppField extends StatelessWidget {
  const AppField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.onChanged,
    this.onSubmitted,
    this.suffix,
    this.obscure = false,
    this.private = false,
    this.keyboardType,
    this.autofillHints,
    this.maxLines = 1,
    this.autofocus = false,
  });

  final TextEditingController controller;

  /// Whether the field takes the focus when it first shows.
  final bool autofocus;

  /// The accessible name. The field has no visible label of its own.
  final String label;
  final String? hint;

  /// Called on an edit by the person, not when the controller's text is set in code.
  final ValueChanged<String>? onChanged;

  /// Called when the person presses Enter.
  final ValueChanged<String>? onSubmitted;

  /// A widget drawn inside the field, after the text.
  final Widget? suffix;

  /// Hides the text, as for a key.
  final bool obscure;

  /// Keeps the keyboard from learning the text, whether or not it is hidden, as for a key.
  final bool private;

  final TextInputType? keyboardType;

  /// What the system may fill in, such as a web address. Null, the default, leaves the field
  /// out of autofill, so a key is never offered a saved password.
  final Iterable<String>? autofillHints;

  /// More than 1 makes a box of text that starts 3 lines tall and grows to this many.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    const height = Sizes.field;
    const size = 16.0;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(Sizes.control),
          borderSide: BorderSide(color: color, width: width),
          gapPadding: 0,
        );
    // Several lines are set apart, as the design canvas sets a text area.
    final text = Type.sans(
      size,
      height: maxLines > 1 ? Type.textAreaLine : null,
    );
    return Semantics(
      label: label,
      textField: true,
      child: TextField(
        autofocus: autofocus,
        controller: controller,
        autocorrect: false,
        // Flutter on Android marks a field without suggestions as a visible password, which
        // would replace a web-address or multiline keyboard and invite a saved login. A URL
        // keyboard offers no word suggestions anyway.
        enableSuggestions: keyboardType == TextInputType.url || maxLines > 1,
        obscureText: obscure,
        keyboardType:
            keyboardType ?? (maxLines > 1 ? TextInputType.multiline : null),
        minLines: maxLines > 1 ? math.min(4, maxLines) : null,
        maxLines: maxLines,
        autofillHints: autofillHints,
        enableIMEPersonalizedLearning: !private,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: text.copyWith(color: t.ink),
        cursorColor: t.accent,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: fieldFill(context),
          hintText: hint,
          hintStyle: text.copyWith(color: t.muted),
          suffixIcon: suffix == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: suffix,
                ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 13,
            vertical: (height - 18) / 2,
          ),
          constraints: BoxConstraints(minHeight: height),
          enabledBorder: border(fieldEdge(context)),
          focusedBorder: border(t.accent, 2),
        ),
      ),
    );
  }
}

/// An [AppField] for a secret such as a key: hidden until Show is pressed, and Hide hides it
/// again. Both are heard with the field's [label], and the keyboard never learns the text.
class SecretField extends StatefulWidget {
  const SecretField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;

  @override
  State<SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<SecretField> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final verb = _shown ? 'Hide' : 'Show';
    return AppField(
      controller: widget.controller,
      label: widget.label,
      hint: widget.hint,
      obscure: !_shown,
      private: true,
      keyboardType: widget.keyboardType,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      suffix: Tappable(
        label: '$verb ${widget.label}',
        toggled: _shown,
        touchTarget: true,
        onTap: () => setState(() => _shown = !_shown),
        radius: BorderRadius.circular(Sizes.small),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(
            verb,
            style: Type.sans(14, weight: FontWeight.w600, color: t.accent),
          ),
        ),
      ),
    );
  }
}

/// A choice among [choices], drawn as a field: as tall as an [AppField] and rounded, with
/// Not set while [value] is none of them. A null [onChanged] turns it off.
class AppSelect extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.labelOf,
  });

  final String? value;
  final List<String> choices;
  final ValueChanged<String?>? onChanged;

  /// What a choice is called, when that is not the choice itself.
  final String Function(String choice)? labelOf;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final radius = BorderRadius.circular(Sizes.control);
    return Container(
      height: Sizes.field,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: fieldFill(context),
        border: Border.all(color: fieldEdge(context)),
        borderRadius: radius,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: choices.contains(value) ? value : null,
          hint: Text('Not set', style: Type.sans(15, color: t.muted)),
          style: Type.sans(15, color: t.ink),
          dropdownColor: t.panel,
          borderRadius: radius,
          icon: RotatedBox(
            quarterTurns: 1,
            child: AppIcon('chevron', size: IconSize.xs, color: t.muted),
          ),
          items: [
            for (final choice in choices)
              DropdownMenuItem(
                value: choice,
                child: Text(labelOf?.call(choice) ?? choice),
              ),
          ],
          onChanged: onChanged,
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
