import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

/// The syntaxes that make TeX in an answer a `math` element, whose `display` attribute says
/// whether it stands on its own: `$$...$$` and `\[...\]` do, `$...$` and `\(...\)` sit in the
/// text. A dollar pair is math only as pandoc reads it: the opening `$` has no space after it,
/// and the closing `$` has no space before it and no digit after it, so prices such as
/// "$5 and $10" stay text. Each is tried only where its first character is.
final mathSyntaxes = <md.InlineSyntax>[
  _MathSyntax(
    r'\$\$([\s\S]+?)\$\$|\$(?!\s)((?:\\.|[^$\\\n])+?)(?<!\s)\$(?!\d)',
    0x24, // $
  ),
  _MathSyntax(r'\\\[([\s\S]+?)\\\]|\\\(([\s\S]+?)\\\)', 0x5C), // \
];

/// One of [mathSyntaxes]: its first group is display math, its second math in the text.
class _MathSyntax extends md.InlineSyntax {
  _MathSyntax(super.pattern, int start) : super(startCharacter: start);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match[1] != null;
    parser.addNode(
      md.Element.text('math', (match[1] ?? match[2])!.trim())
        ..attributes['display'] = '$display',
    );
    return true;
  }
}

/// Draws a `math` element from [mathSyntaxes] in [style]. Display math scrolls sideways rather
/// than widen the chat. TeX that does not parse shows as its source in [fallback].
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: math,
    );
  }
}
