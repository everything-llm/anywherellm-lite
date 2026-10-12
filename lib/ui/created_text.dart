import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/created.dart';
import '../core/outputs.dart';
import 'app_scope.dart';
import 'chat/answer_body.dart';
import 'files/created_files.dart';
import 'icons.dart';
import 'layout.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/basics.dart';
import 'widgets/buttons.dart';
import 'widgets/phone_page.dart';

/// A phone's view of one Markdown file the agent's code left in the workspace, over Artifacts:
/// its name under a round Back, which gives the list back, with Download as the header's action,
/// and the file drawn as an answer is. A file over [CreatedText.maxBytes] is not read.
class CreatedText extends StatefulWidget {
  const CreatedText(this.file, {super.key});

  final CreatedFile file;

  /// The most a file may hold to be read and drawn here: 2 MB.
  static const maxBytes = 2 * 1024 * 1024;

  @override
  State<CreatedText> createState() => _CreatedTextState();
}

class _CreatedTextState extends State<CreatedText> {
  late final _scope = AppScope.of(context);

  /// The file's text once read, or null while it is read or when it could not be.
  String? _text;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.file.size <= CreatedText.maxBytes) unawaited(_read());
  }

  Future<void> _read() async {
    setState(() => _loading = true);
    final bytes = await _scope.created.bytes(widget.file);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _text = bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final file = widget.file;
    final shell = _scope.shell;
    final muted = Type.sans(14, color: t.muted);
    final Widget body;
    if (file.size > CreatedText.maxBytes) {
      body = Text(
        'At ${sizeText(file.size)} it is too long to show here. Download it to read it.',
        style: muted,
      );
    } else if (_loading) {
      body = Text('Reading…', style: muted);
    } else if (_text case final text?) {
      body = Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: t.panel,
          border: Border.all(color: t.line2),
          borderRadius: BorderRadius.circular(Sizes.phoneCard),
        ),
        child: AnswerBody(text, label: _scope.labelAnswers),
      );
    } else {
      body = AlertBox(
        AlertKind.bad,
        'Could not read ${file.name}',
        text: _scope.created.problem?.text,
        action: AppButton('Try again', onPressed: () => unawaited(_read())),
      );
    }
    return ColoredBox(
      color: t.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhonePageHeader(
            title: file.name,
            back: 'Back to Artifacts',
            onBack: shell.closeCreatedText,
            action: IconBtn(
              'download',
              tooltip: 'Download ${file.name}',
              box: 48,
              filled: true,
              size: IconSize.small,
              onPressed: () => unawaited(saveCreated(context, file)),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [body],
            ),
          ),
        ],
      ),
    );
  }
}
