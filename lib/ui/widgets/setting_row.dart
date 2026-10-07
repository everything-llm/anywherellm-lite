import 'package:flutter/material.dart';

import '../tokens.dart';
import '../type.dart';
import 'fields.dart';

/// A label, its control, and a line of help, or the problem with what was typed.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    required this.help,
    required this.child,
    this.problem,
  });

  final String label;
  final String help;
  final String? problem;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: Type.sans(14, weight: FontWeight.w600, color: t.ink),
          ),
          const SizedBox(height: 8),
          child,
          const SizedBox(height: 6),
          if (problem case final text?)
            Text(text, style: Type.sans(12.5, color: t.badfg, height: 1.45))
          else
            HelpText(help),
        ],
      ),
    );
  }
}
