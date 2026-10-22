import 'dart:async';

import 'package:flutter/material.dart';

import '../core/copy.dart';
import '../core/ports.dart';
import '../core/skill_pages.dart';
import 'app_scope.dart';
import 'links.dart';
import 'settings/rows.dart';
import 'widgets/phone_page.dart';

/// What the suite's skills add to the shelf, a card under a 20 px gap with a row for each of
/// their pages that is set up: the app manager, the Library and the Vault. It reads which pages are set up each
/// time it opens. A row reads where the page is afresh at the tap, opens it, and closes the shelf
/// once the read is back, so the page or the notice shows; the page's address is never kept. It
/// shows nothing while none is set up.
class ToolkitCard extends StatefulWidget {
  const ToolkitCard({super.key});

  @override
  State<ToolkitCard> createState() => _ToolkitCardState();
}

class _ToolkitCardState extends State<ToolkitCard> {
  @override
  void initState() {
    super.initState();
    AppScope.of(context).toolkit.wantPages();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.toolkit, scope.chat]),
      builder: (context, _) {
        final toolkit = scope.toolkit;
        toolkit.wantPagesOnce();
        final rows = [
          if (toolkit.pagesServed)
            for (final page in SkillPage.values)
              if (page.listing case final listing?
                  when toolkit.pagesFound.contains(page))
                NavRow(
                  icon: listing.icon,
                  title: listing.title,
                  about: listing.about,
                  onTap: () => _open(page, listing),
                ),
        ];
        if (rows.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: FieldCard(rows),
        );
      },
    );
  }

  /// Opens [page], listed as [listing], then closes the shelf once the read is back, so the
  /// page or the notice shows.
  Future<void> _open(SkillPage page, PageListing listing) async {
    final shell = AppScope.of(context).shell;
    await openListedPage(context, page, listing);
    shell.closeShelf();
  }
}

/// Opens [page], listed as [listing], at the address the toolkit gives now, on the connected
/// server. A failure, or a page not set up, shows as a notice in the chat. The address is held by
/// this call alone.
Future<void> openListedPage(
  BuildContext context,
  SkillPage page,
  PageListing listing,
) async {
  final called = listing.called;
  final scope = AppScope.of(context);
  try {
    final path = await scope.toolkit.pagePath(page);
    if (!context.mounted) return;
    final server = scope.settings.connection?.uri;
    if (path == null || server == null) {
      scope.chat.reportLink(
        '${capitalized(called)} is not set up yet',
        listing.setUp,
      );
    } else {
      // What holds the row opens it first, since it needs the row's context.
      unawaited(openSkillPage(context, page, server.resolve(path)));
    }
  } on ApiException catch (error) {
    scope.chat.reportLink('Could not open $called', error.message);
  }
}
