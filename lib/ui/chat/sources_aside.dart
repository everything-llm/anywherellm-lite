import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/server_models.dart';
import '../../core/sources.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../links.dart';
import '../settings/rows.dart';
import '../state/chat_controller.dart';
import '../state/shell_controller.dart';
import '../state/turn.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/tappable.dart';
import 'passages_sheet.dart';

/// The answer the Sources panel follows, and the source of it chosen, worked out once each
/// time the chat or the choice ([ShellController.aside]) changes, and told only when that
/// changes: the choice while its answer is on screen with sources, else the chat's latest
/// finished answer with sources.
class FollowedSource extends ValueNotifier<AsideChoice?> {
  FollowedSource(this._chat, this._choice) : super(null) {
    _chat.addListener(_update);
    _choice.addListener(_update);
    _update();
  }

  final ChatController _chat;
  final ValueListenable<AsideChoice?> _choice;

  void _update() {
    final next = _follows(_chat.turns, _choice.value);
    if (identical(next?.turn, value?.turn) && next?.source == value?.source) {
      return;
    }
    value = next;
  }

  static AsideChoice? _follows(List<Turn> turns, AsideChoice? choice) {
    if (choice != null &&
        choice.turn.citations.isNotEmpty &&
        turns.any((t) => identical(t, choice.turn))) {
      return choice;
    }
    for (final turn in turns.reversed) {
      if (!turn.streaming && turn.citations.isNotEmpty) {
        return AsideChoice(turn);
      }
    }
    return null;
  }

  @override
  void dispose() {
    _chat.removeListener(_update);
    _choice.removeListener(_update);
    super.dispose();
  }
}

/// Hands the chat's [FollowedSource] to the panel and to each answer's sources below it.
class FollowedScope extends InheritedNotifier<FollowedSource> {
  const FollowedScope({
    super.key,
    required FollowedSource super.notifier,
    required super.child,
  });

  /// The chat's [FollowedSource]; it does not make [context] depend on it.
  static FollowedSource of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FollowedScope>()!.notifier!;
}

/// The Sources panel beside the chat on a wide window: the sources of the answer it follows
/// ([FollowedSource]), numbered as its chips are, each with where it was read and the closest
/// passage, the one a chip picked marked as chosen. Under the list, the chosen source opens: a
/// document in Documents, a web page in the browser.
class SourcesAside extends StatelessWidget {
  const SourcesAside({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final follow = FollowedScope.of(context);
    return Semantics(
      container: true,
      label: 'Sources',
      explicitChildNodes: true,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: cardDecoration(Tokens.of(context)),
        child: ListenableBuilder(
          listenable: Listenable.merge([follow, scope.sources]),
          builder: (context, _) {
            final t = Tokens.of(context);
            final followed = follow.value;
            final cited = followed?.turn.citations ?? const <Citation>[];
            final chosen = followed?.source;
            final web = cited.every((c) => c.url != null);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          'Sources',
                          style: Type.body(t.ink, weight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        followed == null
                            ? 'The sources an answer draws on show here.'
                            : web
                            ? '${plural(cited.length, 'web page', 'web pages')} the agent read.'
                            : plural(cited.length, 'source', 'sources'),
                        style: Type.note(t.ink),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: cited.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _AsideRow(
                      cited[i],
                      number: i + 1,
                      chosen: chosen == i,
                      onTap: () => scope.shell.aside.value = AsideChoice(
                        followed!.turn,
                        i,
                      ),
                    ),
                  ),
                ),
                if (followed != null)
                  _Foot(chosen == null ? null : cited[chosen]),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One source in the panel: its number, its title (a web page by its site), how close its
/// closest passage came, and that passage.
class _AsideRow extends StatelessWidget {
  const _AsideRow(
    this.citation, {
    required this.number,
    required this.chosen,
    required this.onTap,
  });

  final Citation citation;
  final int number;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final url = citation.url;
    final live = url != null || scope.sources.byTitle(citation.title) != null;
    final passage = citation.passages.firstOrNull?.text.trim();
    final score = citation.passages.firstOrNull?.score;
    final match = score == null ? null : matchText(score);
    final title = citedName(citation);
    const radius = BorderRadius.all(Radius.circular(Sizes.control));
    // Chosen, it is filled with the accent's tint and barred in the accent at its start, as a
    // selected row is.
    return ClipRRect(
      borderRadius: radius,
      child: Tappable(
        label: ['Source $number: $title', ?match].join(', '),
        selected: chosen,
        onTap: onTap,
        radius: radius,
        color: chosen ? t.accentSoft : t.ground,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: chosen ? t.accent : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 6,
              children: [
                Row(
                  spacing: 10,
                  children: [
                    CitationNumber(number, live: live),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.body(t.ink, weight: FontWeight.w600),
                      ),
                    ),
                    if (match != null) Text(match, style: Type.note(t.ink)),
                  ],
                ),
                if (passage != null && passage.isNotEmpty)
                  Text(
                    passage,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Type.body(t.ink),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Under the list, what opens the chosen source: Open in Documents for a document in the
/// workspace, Open page for a web page; with none chosen, Documents itself.
class _Foot extends StatelessWidget {
  const _Foot(this.chosen);

  final Citation? chosen;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final url = chosen?.url;
    final title = chosen?.title;
    final present = title != null && scope.sources.byTitle(title) != null;
    final Widget button;
    if (url != null) {
      button = _FootAction(
        'Open page',
        icon: 'external',
        onTap: () => openLink(context, url),
      );
    } else if (chosen == null || present) {
      button = _FootAction(
        'Open in Documents',
        icon: 'doc',
        // The panel shows only on a wide window, where Documents is a pane.
        onTap: () => present
            ? showCitedInDocuments(context, title)
            : scope.shell.openSources(asPane: true),
      );
    } else {
      return const SizedBox.shrink();
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: button,
      ),
    );
  }
}

/// The panel's foot: [label] after its [icon], in the accent, as a row across the panel.
class _FootAction extends StatelessWidget {
  const _FootAction(this.label, {required this.icon, required this.onTap});

  final String label;
  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: label,
      onTap: onTap,
      radius: BorderRadius.circular(Sizes.small),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Tappable.touchSide),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            spacing: 8,
            children: [
              AppIcon(icon, size: IconSize.small, color: t.accent),
              Flexible(child: Text(label, style: Type.label(t.accent))),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a source goes by in a line or a list of them: a web page by its site, as a row of them
/// reads best, anything else by its title.
String citedName(Citation citation) => citation.url?.host ?? citation.title;
