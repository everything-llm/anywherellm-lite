import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';

/// A text field's outline: on a phone the fainter [Tokens.line2], as the design canvas draws it.
Color fieldEdge(BuildContext context) => ScreenClass.ofContext(context).isPhone
    ? Tokens.of(context).line2
    : Tokens.of(context).line;

/// A text field's fill: on a phone [Tokens.panel], as the design canvas draws it, else
/// [Tokens.bg].
Color fieldFill(BuildContext context) => ScreenClass.ofContext(context).isPhone
    ? Tokens.of(context).panel
    : Tokens.of(context).bg;

/// The look of a text area that fills its space, such as the prompt editor: [fill] behind it,
/// [fieldEdge] round it, and the accent, 2 px, while it has the focus. [padding] is round the
/// text, 14 on every side unless given.
InputDecoration editorDecoration(
  BuildContext context,
  Color fill, {
  EdgeInsets? padding,
}) {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Sizes.controlOf(context)),
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

/// The input: one line 44px tall, 48 on a phone, or [maxLines] lines, rounded, a ring in the
/// accent on focus.
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
    this.focusNode,
  });

  final TextEditingController controller;

  /// The field's focus, for something else to move to it, or null for its own.
  final FocusNode? focusNode;

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
    final height = Sizes.fieldOf(context);
    final size = ScreenClass.ofContext(context).isPhone ? 15.5 : 15.0;
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(Sizes.controlOf(context)),
          borderSide: BorderSide(color: color, width: width),
          gapPadding: 0,
        );
    return Semantics(
      label: label,
      textField: true,
      child: TextField(
        focusNode: focusNode,
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
        style: Type.sans(size).copyWith(color: t.ink),
        cursorColor: t.accent,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: fieldFill(context),
          hintText: hint,
          hintStyle: Type.sans(size, color: t.fade),
          prefixIcon: icon == null
              ? null
              : Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 15, right: 4),
                    child: AppIcon(icon!, size: IconSize.sm, color: t.muted),
                  ),
                ),
          suffixIcon: suffix == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: suffix,
                ),
          prefixIconConstraints: BoxConstraints(minHeight: height),
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

/// A choice among [choices], drawn as a field: as tall as an [AppField] and rounded, with
/// [hint] while [value] is none of them. A null [onChanged] turns it off.
class AppSelect extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.hint = 'Not set',
    this.labelOf,
  });

  final String? value;
  final List<String> choices;
  final ValueChanged<String?>? onChanged;
  final String hint;

  /// What a choice is called, when that is not the choice itself.
  final String Function(String choice)? labelOf;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final radius = BorderRadius.circular(Sizes.controlOf(context));
    return Container(
      height: Sizes.fieldOf(context),
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
          hint: Text(hint, style: Type.sans(15, color: t.fade)),
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
