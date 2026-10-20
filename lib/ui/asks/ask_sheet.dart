import 'package:flutter/material.dart';

import '../../core/asks.dart';
import '../../core/copy.dart';
import '../app_scope.dart';
import '../settings/rows.dart';
import '../state/ask_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/sheet.dart';

/// Allow this?, over the whole window while a skill waits on the person ([AskController.current]):
/// what it asks to reach and why, in which workspace, and until when, then Allow once, Always
/// allow and Deny. Esc, Back, Close and the scrim refuse it, as Deny does. A request that could
/// not be read, or no longer waits, says why over Close.
class AskSheet extends StatelessWidget {
  const AskSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final asks = AppScope.of(context).asks;
    return ListenableBuilder(
      listenable: asks,
      builder: (context, _) {
        final shown = asks.current.value;
        if (shown == null) return const SizedBox.shrink();
        return ModalSheet(
          key: ObjectKey(shown),
          title: 'Allow this?',
          onClose: asks.dismiss,
          child: _AskBody(shown),
        );
      },
    );
  }
}

class _AskBody extends StatelessWidget {
  const _AskBody(this.shown);

  final AskShown shown;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final asks = scope.asks;
    final t = Tokens.of(context);
    final ask = shown.ask;
    final workspace = scope.chat.workspaceOf(shown.slug)?.name ?? shown.slug;
    final open = ask != null && !shown.ended;
    VoidCallback? decide(AskDecision decision) =>
        open && !asks.busy ? () => asks.decide(decision) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        // The details scroll, so the buttons stay in reach.
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 16,
              children: [
                if (ask != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '${ask.skill} asks to reach a host on your own network, which it '
                      'cannot without you.',
                      style: Type.sans(15.5, color: t.ink, height: 1.5),
                    ),
                  ),
                  FieldCard([
                    InfoRow(
                      'Host',
                      about: ask.origin,
                      aboutLines: 2,
                      mono: true,
                    ),
                    if (ask.why.isNotEmpty)
                      InfoRow('Why', about: ask.why, aboutLines: 4),
                    InfoRow('Workspace', about: workspace),
                  ]),
                  if (open)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'It waits until ${clockText(ask.expires.toLocal())}, then goes on '
                        'without it. Always allow lets every skill reach ${ask.host} from '
                        'now on, even out of a chat.',
                        style: Type.sans(13.5, color: t.muted, height: 1.5),
                      ),
                    ),
                ],
                if (shown.problem case final problem?)
                  AlertBox.notice(
                    shown.ended ? AlertKind.info : AlertKind.bad,
                    problem,
                  ),
              ],
            ),
          ),
        ),
        if (open) ...[
          AppButton(
            'Allow once',
            primary: true,
            onPressed: decide(AskDecision.once),
          ),
          ActionRow(even: true, [
            AppButton('Always allow', onPressed: decide(AskDecision.always)),
            AppButton(
              'Deny',
              danger: true,
              onPressed: decide(AskDecision.deny),
            ),
          ]),
        ] else
          AppButton('Close', onPressed: asks.dismiss),
      ],
    );
  }
}
