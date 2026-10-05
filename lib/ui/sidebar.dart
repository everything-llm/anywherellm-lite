import 'package:flutter/material.dart';

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
      listenable: scope.nav,
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
  });

  final String icon;
  final String label;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: label,
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
          ],
        ),
      ),
    );
  }
}
