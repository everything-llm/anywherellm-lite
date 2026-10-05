import 'package:flutter/widgets.dart';

import '../../core/copy.dart';
import '../../core/models.dart';
import 'basics.dart';
import 'rows.dart';

/// What the last check found, one row each. [showLibrary] says which library a finding is in,
/// for a page that lists both.
class FindingsSection extends StatelessWidget {
  const FindingsSection(this.findings, {super.key, this.showLibrary = false});

  final List<Finding> findings;
  final bool showLibrary;

  @override
  Widget build(BuildContext context) => ListSection('To look at', [
    for (final f in findings)
      NilsRow(
        title: f.path,
        meta: showLibrary ? '${f.library}: ${f.message}' : f.message,
        badges: [NilsBadge(severityBadge(f.severity))],
      ),
  ]);
}
