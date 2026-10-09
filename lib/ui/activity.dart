import 'dart:async';

import 'package:flutter/material.dart';

import '../core/activity.dart';
import '../core/server_models.dart';
import 'app_scope.dart';
import 'icons.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/basics.dart';
import 'widgets/buttons.dart';
import 'widgets/fields.dart';
import 'widgets/phone_page.dart';
import 'widgets/tappable.dart';

/// Activity in a phone's drawer: how many answers the relay is writing, once read. It reads
/// them the first time it shows on a server. Tapped, it opens [ActivityPage].
class ActivityRow extends StatefulWidget {
  const ActivityRow({super.key});

  @override
  State<ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends State<ActivityRow> {
  @override
  void initState() {
    super.initState();
    final system = AppScope.of(context).system;
    // A read tells the controller's listeners at once, so it waits for the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          system.activity == null &&
          system.activityProblem == null) {
        unawaited(system.readActivity());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: scope.system,
      builder: (context, _) {
        final running = scope.system.running ?? 0;
        return Tappable(
          label: running == 0 ? 'Activity' : 'Activity, $running running',
          onTap: () {
            scope.shell
              ..closeSide()
              ..openActivity();
          },
          radius: BorderRadius.circular(10),
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  AppIcon('activity', size: IconSize.xs, color: t.ink2),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Activity',
                      style: Type.sans(
                        15,
                        weight: FontWeight.w500,
                        color: t.ink,
                      ),
                    ),
                  ),
                  if (running > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: t.accentbg,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$running running',
                        style: Type.sans(12, color: t.accent, height: 1.5),
                      ),
                    ),
                ],
              ),
            ),
          ),
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
            onBack: shell.closeActivity,
            actions: [
              IconBtn(
                'refresh',
                tooltip: 'Read the list again',
                box: 44,
                size: IconSize.small,
                onPressed: () => unawaited(scope.system.readActivity()),
              ),
            ],
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([scope.system, scope.chat]),
              builder: (context, _) => _body(context, scope, t),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, AppScope scope, Tokens t) {
    final system = scope.system;
    final runs = system.activity;
    final now = DateTime.now();
    final running = [
      for (final run in runs ?? const <RelayRun>[])
        if (run.running) run,
    ]..sort((a, b) => _at(b.started).compareTo(_at(a.started)));
    final finished =
        [
          for (final run in runs ?? const <RelayRun>[])
            if (!run.running) run,
        ]..sort(
          (a, b) =>
              _at(b.finished ?? b.started)
                  .compareTo(_at(a.finished ?? a.started)),
        );
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          sliver: SliverList.list(
            children: [
              if (system.activityProblem case final problem?) ...[
                const SizedBox(height: 18),
                AlertBox(AlertKind.warn, problem.title, text: problem.text),
              ] else if (runs == null) ...[
                const SizedBox(height: 18),
                Text('Reading…', style: Type.sans(14, color: t.muted)),
              ] else if (runs.isEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Nothing has been answered in the last 7 days.',
                  style: Type.sans(14, color: t.muted),
                ),
              ],
              if (running.isNotEmpty) ...[
                _Heading('Running now'),
                for (final (i, run) in running.indexed)
                  _RunRow(run, first: i == 0, now: now),
              ],
              if (finished.isNotEmpty) ...[
                _Heading('Finished, last 7 days'),
                for (final (i, run) in finished.indexed)
                  _RunRow(run, first: i == 0, now: now),
              ],
            ],
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: const HelpText(
                'Answers the server has run, in every workspace. Research and delegation show as cards in their chats.',
              ),
            ),
          ),
        ),
      ],
    );
  }

  static DateTime _at(DateTime? time) =>
      time ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 2),
    child: SectionLabel(text),
  );
}

/// One answer: where it was asked, the question, and how it stands.
class _RunRow extends StatelessWidget {
  const _RunRow(this.run, {required this.first, required this.now});

  final RelayRun run;
  final bool first;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final chat = scope.chat;
    final workspace = chat.workspaces
        .where((w) => w.slug == run.workspace)
        .firstOrNull;
    final thread = chat
        .threadsOf(run.workspace)
        .where((c) => c.slug == run.thread)
        .firstOrNull;
    final where = [
      ?workspace?.name,
      thread?.name ?? 'A chat that is gone',
    ].join(' · ');
    final question = run.question ?? 'A question the relay did not keep';
    final (label, color, ended) = _state(t);
    final fresh = run.done && chat.isReady(run.thread);
    final started = run.started;
    final took = run.running && started != null
        ? elapsedText(now.difference(started))
        : null;
    final heard = [
      where,
      question,
      label,
      ?(took ?? ended),
      if (fresh) 'not opened yet',
    ].join(', ');
    return Container(
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: t.line2)),
      ),
      child: Row(
        spacing: 4,
        children: [
          Expanded(
            child: Tappable(
              label: heard,
              onTap: thread == null ? null : () => _open(scope),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
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
                          if (fresh)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: t.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      Text(
                        question,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Type.sans(15, color: t.ink, height: 1.4),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: label,
                              style: Type.sans(
                                12.5,
                                weight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                            if (took ?? ended case final tail?)
                              TextSpan(text: ' · $tail'),
                          ],
                        ),
                        style: Type.sans(12.5, color: t.muted),
                      ),
                      if (run.failed && run.error != null)
                        Text(
                          run.error!,
                          style: Type.sans(12.5, color: t.badfg, height: 1.4),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (run.running)
            Tappable(
              label: 'Stop this answer',
              onTap: () => unawaited(scope.system.stopRun(run)),
              radius: BorderRadius.circular(9),
              child: SizedBox.square(
                dimension: 44,
                child: Center(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: t.ink,
                      borderRadius: BorderRadius.circular(9),
                    ),
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
            ),
        ],
      ),
    );
  }

  /// The word for how the answer stands, its colour, and when it ended.
  (String, Color, String?) _state(Tokens t) {
    final ended = run.finished ?? run.started;
    final ago = ended == null ? null : agoText(ended, now);
    return switch (run.status) {
      'running' => ('Answering', t.accent, null),
      'done' => ('Done', t.okfg, ago),
      'failed' => ('Failed', t.badfg, ago),
      'cancelled' => ('Stopped', t.muted, ago),
      _ => (run.status, t.muted, ago),
    };
  }

  /// Opens the chat the answer belongs to.
  void _open(AppScope scope) {
    scope.shell
      ..closeActivity()
      ..closeSide()
      ..showPane(Pane.chats);
    unawaited(scope.chat.select(run.workspace, thread: run.thread));
  }
}
