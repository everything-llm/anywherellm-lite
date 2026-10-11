import 'package:flutter/widgets.dart';

import '../tokens.dart';
import '../type.dart';

/// A screen's big line, such as Ask about Q3 planning.: [before], then [name] in the accent,
/// then [after], at 32 in [Tokens.ink2].
class Headline extends StatelessWidget {
  const Headline(
    this.before, {
    super.key,
    this.name,
    this.after = '',
    this.textAlign,
  });

  final String before;
  final String? name;
  final String after;
  final TextAlign? textAlign;

  /// The style of a headline in [context].
  static TextStyle styleOf(BuildContext context) => Type.sans(
    32,
    weight: FontWeight.w500,
    color: Tokens.of(context).ink2,
    height: 1.15,
    letterSpacing: -0.8,
  );

  @override
  Widget build(BuildContext context) {
    final style = styleOf(context);
    return Semantics(
      header: true,
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(text: before),
            if (name case final name?)
              TextSpan(
                text: name,
                style: Type.sans(
                  32,
                  weight: FontWeight.w700,
                  color: Tokens.of(context).accent,
                  height: 1.15,
                  letterSpacing: -0.8,
                ),
              ),
            TextSpan(text: after),
          ],
        ),
        textAlign: textAlign,
      ),
    );
  }
}
