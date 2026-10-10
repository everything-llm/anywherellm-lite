import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../app_scope.dart';
import '../state/chat_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/tappable.dart';

/// A tool the agent will not run until the person allows it: what it is, what it will do, its
/// arguments on request, and Allow or Deny. The server refuses the tool by itself when the time
/// the card counts down runs out, and the card then says so and asks nothing.
class ApprovalCard extends StatefulWidget {
  const ApprovalCard(this.turn, this.request, {super.key});

  final Turn turn;
  final ApprovalRequest request;

  @override
  State<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<ApprovalCard> {
  bool _details = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_left <= Duration.zero) _tick?.cancel();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Duration get _left => widget.request.expires.difference(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final request = widget.request;
    final left = _left;
    final expired = left <= Duration.zero;
    final chat = AppScope.of(context).chat;
    final arguments = request.payload.isEmpty
        ? null
        : const JsonEncoder.withIndent('  ').convert(request.payload);
    return Semantics(
      liveRegion: true,
      child: AlertBox(
        AlertKind.warn,
        expired ? 'Not answered in time' : 'Allow ${request.skill}?',
        text: expired
            ? 'The server refused ${request.skill}, and the agent went on without it.'
            : '${request.description ?? 'The agent wants to run this tool.'} '
                  'Refused by itself in ${_clock(left)}.',
        action: expired
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (arguments != null) ...[
                    Tappable(
                      label: _details ? 'Hide details' : 'Show details',
                      expanded: _details,
                      onTap: () => setState(() => _details = !_details),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          _details ? 'Hide details' : 'Show details',
                          style: Type.sans(13, color: t.warnfg),
                        ),
                      ),
                    ),
                    if (_details)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SelectableText(
                          arguments.length > _limit
                              ? '${arguments.substring(0, _limit)}…'
                              : arguments,
                          style: Type.mono(12, color: t.warnfg),
                        ),
                      ),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppButton(
                        'Deny',
                        onPressed: () =>
                            chat.approve(widget.turn, request, false),
                      ),
                      AppButton(
                        'Allow',
                        primary: true,
                        onPressed: () =>
                            chat.approve(widget.turn, request, true),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  /// How much of the arguments the card shows.
  static const _limit = 1500;
}

/// [left] as `1:42`.
String _clock(Duration left) {
  final seconds = left.inSeconds < 0 ? 0 : left.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
