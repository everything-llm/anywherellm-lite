import 'package:flutter/material.dart';

import '../../core/copy.dart';

import '../app_scope.dart';
import '../icons.dart';
import '../state/chat_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/tappable.dart';

/// The everythingllm browser in an answer. While the agent uses it, the chip says its step now,
/// in place of the status line, and a tap shows the chat's browser beside the chat. Once the
/// answer has ended without a card of the browser, it says how many steps the agent took, and a
/// tap lists them.
class BrowserChip extends StatefulWidget {
  const BrowserChip(this.turn, {super.key});

  final Turn turn;

  @override
  State<BrowserChip> createState() => _BrowserChipState();
}

class _BrowserChipState extends State<BrowserChip> {
  bool _listed = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final turn = widget.turn;
    final live = turn.browsing;
    final steps = turn.browserSteps;
    final text = live
        ? 'Browser · ${turn.status}'
        : 'Used the browser · ${plural(steps.length, 'step', 'steps')}';
    final chip = Tappable(
      label: live ? '$text. Show the browser' : text,
      tooltip: live ? 'Show the browser' : null,
      expanded: live ? null : _listed,
      onTap: live
          ? AppScope.of(context).shell.showBrowser
          : () => setState(() => _listed = !_listed),
      radius: BorderRadius.circular(99),
      color: t.accentbg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon('globe', size: IconSize.xs, color: t.accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.sans(12.5, color: t.accent),
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(liveRegion: live, child: chip),
        if (!live && _listed) ...[
          const SizedBox(height: 6),
          BrowserSteps(steps),
        ],
      ],
    );
  }
}

/// The browser's [steps] in an answer, one a line, in order; [now] marks the last as the step
/// the agent is on.
class BrowserSteps extends StatelessWidget {
  const BrowserSteps(this.steps, {super.key, this.now = false});

  final List<String> steps;
  final bool now;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, step) in steps.indexed)
          if (now && i == steps.length - 1)
            _step(i, step, t.ink, FontWeight.w600)
          else
            _step(i, step, t.muted, FontWeight.w400),
      ],
    );
  }

  Widget _step(int i, String step, Color color, FontWeight weight) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 2),
    child: Text(
      '${i + 1}. $step',
      style: Type.sans(12.5, color: color, weight: weight, height: 1.45),
    ),
  );
}

/// Builds [builder] from the chat on screen, the server's word on its browser and the answer
/// running in it, again when the chat changes or that answer's status does, never for each
/// piece of its text.
class BrowserStateBuilder extends StatelessWidget {
  const BrowserStateBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, Turn? running) builder;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    return ListenableBuilder(
      listenable: Listenable.merge([chat, scope.browser]),
      builder: (context, _) {
        final running = chat.runningHere;
        return running == null
            ? builder(context, null)
            : ListenableBuilder(
                listenable: running.statusChanges,
                builder: (context, _) => builder(context, running),
              );
      },
    );
  }
}
