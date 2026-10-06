import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../state/system_controller.dart';
import '../widgets/fields.dart';

/// How many vectors the server's database holds, read when it shows. The count covers every
/// workspace; the API has no count for one.
class VectorCount extends StatefulWidget {
  const VectorCount({super.key});

  @override
  State<VectorCount> createState() => _VectorCountState();
}

class _VectorCountState extends State<VectorCount> {
  @override
  void initState() {
    super.initState();
    AppScope.of(context).system.readVectors();
  }

  @override
  Widget build(BuildContext context) {
    final system = AppScope.of(context).system;
    return ListenableBuilder(
      listenable: system,
      builder: (context, _) => HelpText(switch (system) {
        SystemController(problem: final problem?) =>
          '${problem.title}: ${problem.text}',
        SystemController(vectors: final count?, :final vectorDb) =>
          '${_counted(count)}${vectorDb == null ? '' : ' in $vectorDb'}, '
              'across every workspace.',
        _ => 'Counting the vectors…',
      }, status: true),
    );
  }
}

String _counted(int n) => n == 1 ? '1 vector' : '$n vectors';
