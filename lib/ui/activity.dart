import 'dart:async';

import 'package:flutter/material.dart';

import '../core/activity.dart';
import '../core/server_models.dart';
import 'app_scope.dart';
import 'icons.dart';
import 'settings/rows.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/basics.dart';
import 'widgets/buttons.dart';
import 'widgets/drawer_row.dart';
import 'widgets/fields.dart';
import 'widgets/phone_page.dart';
import 'widgets/tappable.dart';

/// Activity in a phone's drawer: how many answers the relay is writing, once read. It reads
/// them when the drawer first opens on a server. Tapped, it opens [ActivityPage].
class ActivityRow extends StatefulWidget {
  const ActivityRow({super.key});

  @override
  State<ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends State<ActivityRow> {
  late final _shell = AppScope.of(context).shell;

  @override
  void initState() {
    super.initState();
    _shell.addListener(_drawerChanged);
  }

  @override
  void dispose() {
    _shell.removeListener(_drawerChanged);
    super.dispose();
  }

  void _drawerChanged() {
    final system = AppScope.of(context).system;
    if (_shell.sideOpen &&
        system.activity == null &&
        system.activityProblem == null) {
      unawaited(system.readActivity());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: scope.system,
      builder: (context, _) {
        final running = scope.system.running ?? 0;
        return DrawerRow(
          icon: 'activity',
          title: 'Activity',
          heard: running == 0 ? 'Activity' : 'Activity, $running running',
          trailing: running == 0 ? null : DrawerCount('$running running'),
          onTap: () {
            scope.shell
              ..closeSide()
              ..openPhonePage(PhonePage.activity);
          },
        );
      },
    );
  }
}

/// A phone's Activity: the answers the relay is writing, then those it finished, failed or
/// stopped in the last 7 days, in every workspace. A row names the workspace and chat, shows
/// the question and how the answer stands; a running one has Stop, and tapping a row opens its
/// chat. It reads the list as it opens and again while an answer runs.
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  Timer? _again;

  @override
  void initState() {
    super.initState();
    final system = AppScope.of(context).system;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(system.readActivity());
    });
    _again = Timer.periodic(const Duration(seconds: 10), (_) {
      if ((system.running ?? 0) > 0) unawaited(system.readActivity());
    });
  }

  @override
  void dispose() {
    _again?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final shell = scope.shell;
    return ColoredBox(
      color: t.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhonePageHeader(
            title: 'Activity',
            back: 'Back to the chat',
            onBack: shell.closePhonePage,
            action: IconBtn(
              'refresh',
              tooltip: 'Read the list again',
              box: 48,
              filled: true,
              size: IconSize.small,
              onPressed: () => unawaited(scope.system.readActivity()),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([scope.system, scope.chat]),
              builder: (context, _) => _body(scope, t),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(AppScope scope, Tokens t) {
    final system = scope.system;
    final chat = scope.chat;
    final groups = system.activity;
    final now = DateTime.now();
    // What each run's chat is called, looked up once for every row.
    final workspaces = {for (final w in chat.workspaces) w.slug: w.name};
    final threads = {
      for (final w in chat.workspaces)
        for (final c in chat.threadsOf(w.slug)) (w.slug, c.slug): c.name,
    };
    Widget row(RelayRun run) {
      final thread = threads[(run.workspace, run.thread)];
      return _RunRow(
        run,
        now: now,
        where: [
          ?workspaces[run.workspace],
          thread ?? 'A chat that is gone',
        ].join(' · '),
        canOpen: thread != null,
        fresh: run.done && chat.isReady(run.thread),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.list(
            children: [
              if (system.activityProblem case final problem?) ...[
                const SizedBox(height: 18),
                AlertBox(AlertKind.warn, problem.title, text: problem.text),
              ] else if (groups == null) ...[
                const SizedBox(height: 18),
                Text('Reading…', style: Type.sans(14, color: t.muted)),
              ] else if (groups.running.isEmpty && groups.ended.isEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Nothing has been answered in the last 7 days.',
                  style: Type.sans(14, color: t.muted),
                ),
              ],
              if (groups != null) ...[
                if (groups.running.isNotEmpty) ...[
                  const _Heading('Running now'),
                  FieldCard([for (final run in groups.running) row(run)]),
                ],
                if (groups.ended.isNotEmpty) ...[
                  const _Heading('Finished, last 7 days'),
                  FieldCard([for (final run in groups.ended) row(run)]),
                ],
              ],
            ],
          ),
        ),
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: HelpText(
                'Answers the server has run, in every workspace. Research and delegation show as cards in their chats.',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: CardHeading(text),
  );
}

/// One answer: where it was asked ([where]), the question, and how it stands. A row [canOpen]
/// while its chat is still there, and is [fresh] while its answer has not been seen.
class _RunRow extends StatelessWidget {
  const _RunRow(
    this.run, {
    required this.now,
    required this.where,
    required this.canOpen,
    required this.fresh,
  });

  final RelayRun run;
  final DateTime now;
  final String where;
  final bool canOpen;
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final question = run.question ?? 'A question the relay did not keep';
    final (label, color) = switch (run) {
      RelayRun(running: true) => ('Answering', t.accent),
      RelayRun(done: true) => ('Done', t.ink),
      RelayRun(failed: true) => ('Failed', t.badfg),
      _ => (run.status == 'cancelled' ? 'Stopped' : run.status, t.muted),
    };
    final started = run.started;
    final ended = run.endedAt;
    final tail = run.running
        ? (started == null ? null : elapsedText(now.difference(started)))
        : (ended == null ? null : agoText(ended, now));
    final why = run.failed ? run.error : null;
    return Padding(
      padding: const EdgeInsets.only(left: FieldCard.inset, right: 8),
      child: Row(
        spacing: 4,
        children: [
          Expanded(
            child: Tappable(
              label: [
                where,
                question,
                label,
                ?tail,
                if (fresh) 'not opened yet',
              ].join(', '),
              onTap: canOpen ? () => _open(scope) : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Row(
                        spacing: 6,
                        children: [
                          Flexible(
                            child: Text(
                              where,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Type.sans(12.5, color: t.muted),
                            ),
                          ),
                          if (fresh) const ReadyDot(gap: false),
                        ],
                      ),
                      Text(
                        question,
                        style: Type.sans(15.5, color: t.ink, height: 1.4),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: label,
                              style: Type.sans(
                                13,
                                weight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                            if (tail != null) TextSpan(text: ' · $tail'),
                            if (why != null) TextSpan(text: ' · $why'),
                          ],
                        ),
                        style: Type.sans(13, color: t.muted, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (run.running)
            _StopButton(() => unawaited(scope.system.stopRun(run))),
        ],
      ),
    );
  }

  /// Opens the chat the answer belongs to.
  void _open(AppScope scope) {
    scope.shell
      ..closePhonePage()
      ..closeSide()
      ..showPane(Pane.chats);
    unawaited(scope.chat.select(run.workspace, thread: run.thread));
  }
}

/// Stops a running answer: a dark square holding a small one, in a 44 px place to tap.
class _StopButton extends StatelessWidget {
  const _StopButton(this.onTap);

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: 'Stop this answer',
      onTap: onTap,
      shape: const CircleBorder(),
      child: SizedBox.square(
        dimension: 44,
        child: Center(
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: t.ink, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: t.bg,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
