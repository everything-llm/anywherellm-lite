import 'package:flutter/material.dart';

import '../core/copy.dart';
import '../core/models.dart';
import 'app_scope.dart';
import 'icons.dart';
import 'layout.dart';
import 'state/nav_controller.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/brand.dart';
import 'widgets/tappable.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.nav, scope.overview]),
      builder: (context, _) {
        final section = scope.nav.route.section;
        return Semantics(
          container: true,
          label: 'Sections',
          child: Container(
            width: Sizes.sidebar,
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
            decoration: BoxDecoration(
              color: t.side,
              border: Border(right: BorderSide(color: t.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 2, 8, 16),
                  child: Align(alignment: Alignment.centerLeft, child: Brand()),
                ),
                for (final e in navEntries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: NavItem(
                      icon: e.icon,
                      label: e.label,
                      current: section == e.route.section,
                      onTap: () => scope.nav.go(e.route),
                      findings: e.library == null
                          ? const []
                          : scope.overview.findingsFor(e.library!),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class NavItem extends StatelessWidget {
  const NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.current,
    required this.onTap,
    this.findings = const [],
  });

  final String icon;
  final String label;
  final bool current;
  final VoidCallback onTap;

  /// What the last check found in this section's library. A badge counts them.
  final List<Finding> findings;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final severe = findings.any((f) => f.severity == 'error');
    final things = findingsNote(findings.length);
    return Tappable(
      label: findings.isEmpty ? label : '$label, $things',
      selected: current,
      onTap: onTap,
      radius: BorderRadius.circular(8),
      color: current ? t.sel : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            NilsIcon(icon, size: IconSize.normal, color: t.ink),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.sans(
                  14.5,
                  weight: current ? FontWeight.w600 : FontWeight.w400,
                  color: t.ink,
                ),
              ),
            ),
            if (findings.isNotEmpty)
              Tooltip(
                message: things,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: severe ? t.badbg : t.warnbg,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${findings.length}',
                    textAlign: TextAlign.center,
                    style: Type.sans(12, color: severe ? t.badfg : t.warnfg),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
