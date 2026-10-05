import 'package:flutter/material.dart';

import '../tokens.dart';
import '../type.dart';

/// The logo tile and the wordmark.
class Brand extends StatelessWidget {
  const Brand({super.key, this.size = 24, this.logo = true});

  final double size;
  final bool logo;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (logo) ...[
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            padding: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: t.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'e',
              style: Type.serif(19, color: t.onaccent, height: 1),
            ),
          ),
          const SizedBox(width: 10),
        ],
        // Shrinks rather than overflows in a narrow sidebar or at a large text scale.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'everything',
              style: Type.serif(
                size,
                color: t.ink,
                letterSpacing: -0.01 * size,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
