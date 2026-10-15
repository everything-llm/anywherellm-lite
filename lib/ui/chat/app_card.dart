import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/apps_lean.dart';
import '../icons.dart';
import '../layout.dart';
import '../links.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/tappable.dart';

/// Draws a quote that [appCardOf] reads as an app's card as an [AppCardView]; any other quote is
/// left to the package.
class AppCardBuilder extends MarkdownElementBuilder {
  AppCardBuilder(this.server);

  final Uri? server;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final card = appCardOf(element, server);
    return card == null ? null : AppCardView(card);
  }
}

/// An app's card: its title over what changed, a chevron after, and a tap that opens its page
/// as the link would ([openAnswerLink]).
class AppCardView extends StatelessWidget {
  const AppCardView(this.card, {super.key});

  final AppCard card;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final about = card.about;
    return Tappable(
      label: [
        card.title,
        if (about.isNotEmpty) about,
        'Open the app',
      ].join(', '),
      onTap: () => unawaited(openAnswerLink(context, card.href)),
      radius: BorderRadius.circular(Sizes.notice),
      color: t.panel,
      side: BorderSide(color: t.line),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            AppIcon('grid', size: IconSize.large, color: t.accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    card.title,
                    style: Type.sans(
                      16,
                      weight: FontWeight.w600,
                      color: t.ink,
                      height: 1.35,
                    ),
                  ),
                  if (about.isNotEmpty)
                    Text(
                      about,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Type.sans(14, color: t.ink2, height: 1.4),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AppIcon('chevron', size: IconSize.xs, color: t.muted),
          ],
        ),
      ),
    );
  }
}
