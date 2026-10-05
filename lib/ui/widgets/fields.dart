import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'buttons.dart';

/// The single-line input: 44px tall, rounded, a ring in the accent on focus.
class NilsField extends StatelessWidget {
  const NilsField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.onChanged,
    this.icon,
    this.suffix,
    this.obscure = false,
  });

  final TextEditingController controller;

  /// The accessible name. The field has no visible label of its own.
  final String label;
  final String? hint;

  /// Called on an edit by the person, not when the controller's text is set in code.
  final ValueChanged<String>? onChanged;

  /// The name of an icon drawn inside the field, before the text.
  final String? icon;

  /// A widget drawn inside the field, after the text.
  final Widget? suffix;

  /// Hides the text. See [SecretField] for one with a button to show it.
  final bool obscure;

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
        enableSuggestions: false,
        obscureText: obscure,
        onChanged: onChanged,
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
                    child: NilsIcon(icon!, size: IconSize.sm, color: t.muted),
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

/// A [NilsField] for a secret: the text is hidden, with a button to show it.
class SecretField extends StatefulWidget {
  const SecretField({
    super.key,
    required this.controller,
    required this.label,
    this.onChanged,
  });

  final TextEditingController controller;

  /// The accessible name, also in the show and hide buttons' tooltips.
  final String label;
  final ValueChanged<String>? onChanged;

  @override
  State<SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<SecretField> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) => NilsField(
    controller: widget.controller,
    label: widget.label,
    onChanged: widget.onChanged,
    obscure: !_shown,
    suffix: IconBtn(
      _shown ? 'eye-off' : 'eye',
      tooltip: '${_shown ? 'Hide' : 'Show'} ${widget.label}',
      onPressed: () => setState(() => _shown = !_shown),
    ),
  );
}

/// A field with its name written above it, and [help] in small text below. The name is also the
/// field's accessible name. [secret] makes it a [SecretField].
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.help,
    this.secret = false,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? help;
  final bool secret;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Text(
          label,
          style: Type.sans(14, weight: FontWeight.w500, color: t.ink),
        ),
        if (secret)
          SecretField(controller: controller, label: label)
        else
          NilsField(controller: controller, label: label, hint: hint),
        if (help != null) HelpText(help!),
      ],
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

/// A field for narrowing a list: a search icon, and the hint doubling as the accessible name.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => NilsField(
    controller: controller,
    label: hint,
    hint: hint,
    icon: 'search',
    onChanged: onChanged,
  );
}
