import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

/// TeX in an answer, made a `math` element whose `display` attribute says whether it stands on
/// its own: `$$...$$` and `\[...\]` do, `\(...\)` and `$...$` sit in the text. A dollar pair is
/// math only as pandoc reads it: the opening `$` has no space after it, and the closing `$` has
/// no space before it and no digit after it, so prices such as "$5 and $10" stay text.
class MathSyntax extends md.InlineSyntax {
  MathSyntax()
    : super(
        r'\$\$([\s\S]+?)\$\$'
        r'|\\\[([\s\S]+?)\\\]'
        r'|\\\(([\s\S]+?)\\\)'
        r'|\$(?!\s)((?:\\.|[^$\\\n])+?)(?<!\s)\$(?!\d)',
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match[1] != null || match[2] != null;
    final tex = (match[1] ?? match[2] ?? match[3] ?? match[4])!.trim();
    parser.addNode(
      md.Element.text('math', tex)..attributes['display'] = '$display',
    );
    return true;
  }
}

/// Draws a `math` element from [MathSyntax] in [style]. Display math scrolls sideways rather
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
