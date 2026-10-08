import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../widgets/side_scroll.dart';

/// Draws a `math` element from `mathSyntaxes` in [style]. Display math scrolls sideways rather
/// than widen the chat, showing its scrollbar while it does ([SideScroll]). TeX that does not
/// parse shows as its source in [fallback].
class MathBuilder extends MarkdownElementBuilder {
  MathBuilder({required this.style, required this.fallback});

  final TextStyle style;
  final TextStyle fallback;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final display = element.attributes['display'] == 'true';
    final tex = element.textContent;
    // Parsed afresh for each widget: flutter_math_fork caches the widgets it builds, GlobalKeys
    // among them, in the parsed tree, so one tree drawn in two places fails.
    final math = Math.tex(
      tex,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textStyle: style,
      onErrorFallback: (_) =>
          Text(display ? '\$\$$tex\$\$' : '\$$tex\$', style: fallback),
    );
    if (!display) return math;
    return SideScroll(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: math,
    );
  }
}
