import 'dart:async';

import 'package:flutter/material.dart';

import '../core/activity.dart';
import '../core/copy.dart';
import '../core/schedule.dart';
import 'app_scope.dart';
import 'icons.dart';
import 'layout.dart';
import 'links.dart';
import 'settings/rows.dart';
import 'state/toolkit_controller.dart';
import 'toolkit_page.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/buttons.dart';
import 'widgets/controls.dart';
import 'widgets/segmented.dart';
import 'widgets/sheet.dart';
import 'widgets/tappable.dart';

/// The sheet over Activity for one event, in the shell's popup so Back closes it.
class ActivityOpen {
  const ActivityOpen(this.key);

  /// [ActivityEvent.key] of the event.
  final String key;

  @override
  bool operator ==(Object other) => other is ActivityOpen && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// What the agent did, newest first, under Today, Yesterday and the days before: each event's
/// kind, title, workspace and time with how it ended, which a tap opens in a sheet that says what
/// it left and leads to where it came from. All or only what failed. It reads the newest events
/// afresh as it opens, from the toolkit, and the older ones on Show more.
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  bool _failedOnly = false;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final toolkit = scope.toolkit;
    final shell = scope.shell;
    return ListenableBuilder(
      listenable: Listenable.merge([toolkit, shell.popup]),
      // Only the sheet follows the popup, so opening one leaves the list as it is.
      child: ToolkitPageFrame(
        title: 'Activity',
        read: toolkit.readActivity,
        action: ToolkitPageFrame.readAgain(toolkit.readActivity),
        body: ListenableBuilder(
          listenable: toolkit,
          builder: (context, _) => _body(context, toolkit),
        ),
      ),
      builder: (context, page) {
        final open = switch (shell.popup.value) {
          final ActivityOpen open => open,
          _ => null,
        };
        final event = toolkit.activity
            ?.where((e) => e.key == open?.key)
            .firstOrNull;
        // An event gone from a read leaves no sheet to close, so the popup goes too.
        if (open != null && event == null && toolkit.activity != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => shell.closePopup(open),
          );
        }
        return PopupSheet(
          open: event != null,
          onClose: shell.closePopup,
          title: 'This run',
          sheet: (context) =>
              event == null ? const SizedBox.shrink() : _EventSheet(event),
          child: page!,
        );
      },
    );
  }

  Widget _body(BuildContext context, ToolkitController toolkit) {
    final events = toolkit.activity;
    final now = DateTime.now();
    final shown = [
      for (final e in events ?? const <ActivityEvent>[])
        if (!_failedOnly || e.outcome == ActivityOutcome.failed) e,
    ];
    // Each day's events together, in the order the toolkit gave them: newest first.
    final days = <String, List<ActivityEvent>>{};
    for (final e in shown) {
      days.putIfAbsent(dayText(e.at, now), () => []).add(e);
    }
    return ListView(
      padding: Sizes.pageIn(context),
      children: [
        if (events == null || toolkit.activityProblem != null)
          NotRead(toolkit.activityProblem)
        else ...[
          Segmented<bool>(
            options: const [(false, 'All'), (true, 'Failed')],
            value: _failedOnly,
            onChanged: (failed) => setState(() => _failedOnly = failed),
          ),
          if (shown.isEmpty) ...[
            const SizedBox(height: 20),
            FieldCard([
              CardNote(
                _failedOnly
                    ? 'Nothing failed in what is kept.'
                    : 'Nothing yet. What the agent does shows here.',
              ),
            ]),
          ],
          for (final MapEntry(key: day, value: list) in days.entries) ...[
            CardHeading(day),
            FieldCard([for (final e in list) _EventRow(e)]),
          ],
          if (toolkit.activityMore) ...[
            const SizedBox(height: 20),
            ActionRow(even: true, [
              AppButton(
                toolkit.activityLoading ? 'Reading…' : 'Show more',
                onPressed: toolkit.activityLoading
                    ? null
                    : () => unawaited(toolkit.moreActivity()),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          const CardCaption('Kept for 30 days.'),
        ],
      ],
    );
  }
}

/// The icon of a kind of event.
String _iconOf(ActivityKind kind) => switch (kind) {
  ActivityKind.task => 'clock',
  ActivityKind.action => 'external',
  ActivityKind.app => 'grid',
  ActivityKind.file => 'doc',
  ActivityKind.other => 'more',
};

/// How an event ended, in a word and its badge's kind, or null for an outcome the app does not
/// know.
(String, BadgeKind)? _ending(ActivityOutcome outcome) => switch (outcome) {
  ActivityOutcome.ok => ('Done', BadgeKind.ok),
  ActivityOutcome.failed => ('Failed', BadgeKind.warn),
  ActivityOutcome.running => ('Running', BadgeKind.accent),
  ActivityOutcome.unknown => null,
};

/// How an event ended, as a badge, or nothing for an outcome the app does not know.
Widget? _tagOf(ActivityOutcome outcome) => switch (_ending(outcome)) {
  (final word, final kind)? => AppBadge(word, kind: kind),
  null => null,
};

/// One event: its icon, title and where and when, with how it ended.
class _EventRow extends StatelessWidget {
  const _EventRow(this.event);

  final ActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final about = [?event.workspace, clockText(event.at.toLocal())].join(' · ');
    final tag = _tagOf(event.outcome);
    return Tappable(
      label: [
        event.title,
        about,
        ?_ending(event.outcome)?.$1.toLowerCase(),
      ].join(', '),
      onTap: () =>
          AppScope.of(context).shell.togglePopup(ActivityOpen(event.key)),
      child: Container(
        constraints: const BoxConstraints(minHeight: Sizes.cardRow),
        padding: const EdgeInsets.symmetric(
          horizontal: FieldCard.inset,
          vertical: 10,
        ),
        child: Row(
          spacing: 14,
          children: [
            AppIcon(_iconOf(event.kind), size: IconSize.large, color: t.ink),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    event.title,
                    style: Type.sans(16, weight: FontWeight.w500, color: t.ink),
                  ),
                  Text(about, style: Type.sans(13, color: t.muted)),
                ],
              ),
            ),
            ?tag,
          ],
        ),
      ),
    );
  }
}

/// One event in a sheet: what it was, how it ended, what it left, and where it leads.
class _EventSheet extends StatelessWidget {
  const _EventSheet(this.event);

  final ActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final t = Tokens.of(context);
    final now = DateTime.now();
    final about = [
      ?event.workspace,
      '${dayText(event.at, now)} ${clockText(event.at.toLocal())}',
    ].join(' · ');
    final tag = _tagOf(event.outcome);
    final link = event.link;
    // Where the event leads, when it has a place: its chat or its page.
    Widget? lead;
    if (link is ChatLink) {
      lead = AppButton(
        'Open the chat',
        primary: true,
        onPressed: () {
          unawaited(scope.chat.select(link.slug, thread: link.thread));
          shell.openChat();
        },
      );
    } else if (link is PageLink) {
      lead = AppButton(
        'Open it',
        primary: true,
        onPressed: () {
          shell.closePopup();
          unawaited(openAnswerLink(context, link.path));
        },
      );
    }
    // It scrolls where large text leaves the sheet too short for what it holds.
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          FieldCard([InfoRow(event.title, about: about, tag: tag)]),
          const SheetLabel('Result'),
          FieldCard([
            CardWords(
              event.detail.isEmpty ? 'Nothing was kept.' : event.detail,
              color: event.outcome == ActivityOutcome.failed ? t.badfg : null,
            ),
          ]),
          ?lead,
        ],
      ),
    );
  }
}
