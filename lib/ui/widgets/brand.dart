import 'package:flutter/material.dart';

import '../tokens.dart';
import '../type.dart';
import 'robin_mark.dart';

/// The logo tile, the robin in [iconInk] on [iconGround] as on the launcher icon, and the
/// wordmark at 34, on a screen of its own.
class Brand extends StatelessWidget {
  const Brand({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          // The launcher icon's colours, the same in both themes.
          decoration: BoxDecoration(
            color: iconGround,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const RobinMark(size: 26, color: iconInk),
        ),
        const SizedBox(width: 10),
        // Shrinks rather than overflows on a narrow screen or at a large text scale.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'AnywhereLLM',
              style: Type.sans(
                34,
                weight: FontWeight.w700,
                color: t.ink,
                letterSpacing: -0.8,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
