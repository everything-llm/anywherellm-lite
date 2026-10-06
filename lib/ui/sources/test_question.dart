import 'package:flutter/material.dart';

import '../../core/server_models.dart';
import '../app_scope.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/tappable.dart';

/// Tests what a question finds in the switched-on files: the passages an answer would get, each
/// with how close it is. Tapping one shows all of it and lights up its file.
class TestQuestion extends StatefulWidget {
  const TestQuestion({super.key});

  @override
  State<TestQuestion> createState() => _TestQuestionState();
}

class _TestQuestionState extends State<TestQuestion> {
  bool _open = false;
  final _question = TextEditingController();

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  void _close() {
    _question.clear();
    AppScope.of(context).sources.clearSearch();
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextAction(
          'chat',
          'Test a question',
          () => setState(() => _open = true),
        ),
      );
    }
    final sources = AppScope.of(context).sources;
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: sources,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppField(
            controller: _question,
            label: 'Question to test',
            hint: 'Ask what an answer would find',
            onSubmitted: sources.search,
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton('Done', onPressed: _close),
              ListenableBuilder(
                listenable: _question,
                builder: (context, _) => AppButton(
                  'Test',
                  primary: true,
                  onPressed: _question.text.trim().isEmpty || sources.searching
                      ? null
                      : () => sources.search(_question.text),
                ),
              ),
            ],
          ),
          if (sources.searching) ...[
            const SizedBox(height: 8),
            const HelpText('Searching…', status: true),
          ] else if (sources.hits case final hits?) ...[
            const SizedBox(height: 8),
            HelpText(
              hits.isEmpty
                  ? 'Nothing in the switched-on files comes close enough.'
                  : 'What an answer would read, closest first:',
              status: true,
            ),
            for (final hit in hits) ...[
              const SizedBox(height: 6),
              _Hit(hit, key: ObjectKey(hit)),
            ],
          ],
          if (sources.hits != null || sources.searching)
            Divider(height: 24, color: t.line),
        ],
      ),
    );
  }
}

class _Hit extends StatefulWidget {
  const _Hit(this.hit, {super.key});

  final SearchHit hit;

  @override
  State<_Hit> createState() => _HitState();
}

class _HitState extends State<_Hit> {
  bool _whole = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final hit = widget.hit;
    final percent = (hit.score * 100).round();
    return Tappable(
      label: '${hit.title}, $percent% close',
      onTap: () {
        setState(() => _whole = !_whole);
        AppScope.of(context).sources.flash(hit.title);
      },
      radius: BorderRadius.circular(Sizes.control),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(Sizes.control),
          border: Border.all(color: t.line2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    hit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(
                      13.5,
                      weight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('$percent%', style: Type.sans(12.5, color: t.muted)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              hit.text,
              maxLines: _whole ? null : 3,
              overflow: _whole ? null : TextOverflow.ellipsis,
              style: Type.sans(13, color: t.ink2, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
