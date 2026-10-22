import 'package:flutter/widgets.dart';

import '../tokens.dart';
import '../type.dart';

/// A screen's big line, such as Connect to your AnythingLLM.: [before], then [name] in the accent,
/// then [after], as House UI's headline: Instrument Sans at 32 in [Tokens.ink].
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
  static TextStyle styleOf(BuildContext context) =>
      Type.headline(Tokens.of(context).ink);

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
                style: style.copyWith(
                  fontWeight: FontWeight.w700,
                  fontVariations: const [FontVariation('wght', 700)],
                  color: Tokens.of(context).accent,
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
