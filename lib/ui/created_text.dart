import 'package:flutter/material.dart';

import '../core/outputs.dart';
import 'app_scope.dart';
import 'chat/answer_body.dart';
import 'settings/rows.dart';
import 'state/created_controller.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/basics.dart';
import 'widgets/buttons.dart';

/// The text of the Markdown file [CreatedController.reading], as a phone's Artifacts shows it in
/// place of its list: drawn as an answer is, in a card. A file over [CreatedController.readMax]
/// is not read.
class CreatedText extends StatelessWidget {
  const CreatedText({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final created = scope.created;
    final file = created.reading!;
    final muted = Type.sans(14, color: Tokens.of(context).muted);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (file.size > CreatedController.readMax)
          Text(
            'At ${sizeText(file.size)} it is too long to show here. Download it to read it.',
            style: muted,
          )
        else if (created.readLoading)
          Text('Reading…', style: muted)
        else if (created.readText case final text?)
          PanelCard(children: [AnswerBody(text, label: scope.labelAnswers)])
        else
          AlertBox(
            AlertKind.bad,
            'Could not read ${file.name}',
            text: created.problem?.text,
            action: AppButton(
              'Try again',
              onPressed: () => created.openText(file),
            ),
          ),
      ],
    );
  }
}
