import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../../core/outputs.dart';
import '../../core/upload.dart';
import '../app_scope.dart';
import '../settings/settings_pages.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/phone_page.dart';
import '../widgets/sheet.dart';
import '../widgets/tappable.dart';
import 'shared_item.dart';

/// What to do with a shared item.
enum _Use { add, ask }

/// Send to AnywhereLLM: what another app shared, the workspace to take it (the open one first,
/// and chosen), and whether to add it to that workspace's documents or ask about it in a new
/// chat there, with a question. An answer asked about runs on the server, so the sheet closes
/// at once. With no server saved it says to connect first.
class ShareSheet extends StatefulWidget {
  const ShareSheet(this.item, {super.key});

  final SharedItem item;

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  late String? _slug = AppScope.of(context).chat.activeSlug;
  _Use _use = _Use.add;
  final _question = TextEditingController();
  bool _working = false;
  String? _problem;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  /// The item's tile, name and the line under it.
  (String, String, String) get _shown => switch (widget.item) {
    SharedLink(:final url, :final title) => (
      'WEB',
      title ?? url.host,
      '${url.host}${url.path == '/' ? '' : url.path}',
    ),
    SharedText(:final text) => ('TXT', 'Text you selected', text),
    SharedFile(:final name, :final size) => (
      _tileOf(name),
      name,
      sizeText(size),
    ),
  };

  static String _tileOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'FILE';
    final ext = name.substring(dot + 1).toUpperCase();
    return ext.length > 4 ? 'FILE' : ext;
  }

  /// What happens to the item, under the button.
  String get _foot => switch ((_use, widget.item)) {
    (_Use.ask, SharedFile()) => 'A file goes with the message, up to 20 MB. The answer keeps running if you leave.',
    (_Use.ask, _) =>
      'It goes in the message. The answer keeps running if you leave.',
    (_Use.add, SharedLink()) => 'The server reads the page and keeps its text.',
    (_Use.add, SharedFile()) =>
      'The server keeps the text it reads from the file, not the file.',
    (_Use.add, SharedText()) => 'Saved as a document of its own.',
  };

  Future<void> _go() async {
    final scope = AppScope.of(context);
    final slug = _slug;
    if (slug == null) return;
    final item = widget.item;
    if (_use == _Use.ask && _question.text.trim().isEmpty) {
      setState(() => _problem = 'Write a question about it.');
      return;
    }
    if (item case SharedFile(:final name, :final size)
        when _use == _Use.ask && size > maxAttachmentBytes) {
      setState(() => _problem = attachmentProblem(name, size));
      return;
    }
    setState(() {
      _working = true;
      _problem = null;
    });
    final chat = scope.chat;
    final shell = scope.shell;
    if (chat.activeSlug != slug) await chat.select(slug);
    if (!mounted) return;
    shell
      ..closeSettings()
      ..showPane(Pane.chats);
    switch (_use) {
      case _Use.add:
        final sources = scope.sources;
        switch (item) {
          case SharedLink(:final url):
            sources.addLink(url.toString());
          case SharedText(:final text):
            final first = text.trim().split('\n').first.trim();
            await sources.addText(
              first.length > 60 ? '${first.substring(0, 60)}…' : first,
              text,
            );
          case SharedFile(:final name, :final read):
            await sources.upload([UploadFile(name: name, read: read)]);
        }
        shell
          ..closeShared()
          ..openSources();
      case _Use.ask:
        final question = _question.text.trim();
        final (message, attachments) = switch (item) {
          SharedLink(:final url) => ('$question\n\n$url', const <Attachment>[]),
          SharedText(:final text) => (
            '$question\n\n> ${text.trim().replaceAll('\n', '\n> ')}',
            const <Attachment>[],
          ),
          SharedFile(:final name, :final read) => (
            question,
            [Attachment.of(name, Uint8List.fromList(await read()))],
          ),
        };
        chat.newChat();
        shell.closeShared();
        await chat.send(message, attachments: attachments);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final shell = scope.shell;
    final (tile, name, about) = _shown;
    return SheetFrame(
      title: 'Send to AnywhereLLM',
      onClose: shell.closeShared,
      maxFraction: 0.92,
      child: SingleChildScrollView(
        child: ListenableBuilder(
          listenable: Listenable.merge([scope.chat, scope.settings]),
          builder: (context, _) {
            final chat = scope.chat;
            final ordered = scope.prefs.prefs.inOrder(
              chat.workspaces,
              (w) => w.slug,
            );
            final active = chat.activeSlug;
            final workspaces = [
              ...ordered.where((w) => w.slug == active),
              ...ordered.where((w) => w.slug != active),
            ];
            final chosen =
                workspaces.where((w) => w.slug == _slug).firstOrNull ??
                workspaces.firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: t.panel2,
                    border: Border.all(color: t.line),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.accentbg,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          tile,
                          style: Type.sans(
                            9.5,
                            weight: FontWeight.w600,
                            color: t.accent,
                            letterSpacing: 0.28,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Type.sans(
                                14.5,
                                weight: FontWeight.w500,
                                color: t.ink,
                              ),
                            ),
                            Text(
                              about,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Type.sans(12.5, color: t.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!scope.settings.configured) ...[
                  const SizedBox(height: 16),
                  const Footnote(
                    'Connect to your AnythingLLM server first, then share it again.',
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    'Open Settings',
                    primary: true,
                    onPressed: () {
                      shell.closeShared();
                      shell.openSettings(SettingsPage.connection);
                    },
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  const SectionLabel('Workspace'),
                  const SizedBox(height: 4),
                  for (final w in workspaces)
                    _Choice(
                      title: w.name,
                      hint: w.slug == active ? 'Open now' : null,
                      selected: w == chosen,
                      onTap: () => setState(() => _slug = w.slug),
                    ),
                  const SizedBox(height: 12),
                  const SectionLabel('What to do with it'),
                  const SizedBox(height: 6),
                  for (final (use, title, detail) in [
                    (
                      _Use.add,
                      'Add to Documents',
                      'Answers in ${chosen?.name ?? 'the workspace'} can draw on it from now on.',
                    ),
                    (
                      _Use.ask,
                      'Ask about it',
                      'Starts a new chat with it attached. It is not kept as a document.',
                    ),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _Choice(
                        title: title,
                        about: detail,
                        selected: _use == use,
                        card: true,
                        onTap: () => setState(() {
                          _use = use;
                          _problem = null;
                        }),
                      ),
                    ),
                  if (_use == _Use.ask) ...[
                    const SizedBox(height: 4),
                    AppField(
                      controller: _question,
                      label: 'Your question',
                      hint: 'What do you want to know?',
                    ),
                  ],
                  if (_problem case final problem?) ...[
                    const SizedBox(height: 8),
                    HelpText(problem, status: true),
                  ],
                  const SizedBox(height: 14),
                  AppButton(
                    _working
                        ? 'Sending…'
                        : _use == _Use.add
                        ? 'Add to Documents'
                        : 'Ask',
                    primary: true,
                    onPressed: _working || chosen == null ? null : _go,
                  ),
                  const SizedBox(height: 10),
                  Footnote(_foot),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One choice of several: a radio ring and [title], with [hint] after it or the line [about]
/// under it; as a [card], in a box filled while chosen.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.selected,
    required this.onTap,
    this.hint,
    this.about,
    this.card = false,
  });

  final String title;
  final String? hint;
  final String? about;
  final bool selected;
  final bool card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: [title, ?hint, ?about].join('. '),
      selected: selected,
      onTap: onTap,
      radius: BorderRadius.circular(12),
      color: card ? (selected ? t.sel : t.panel) : null,
      side: card
          ? BorderSide(color: selected ? Colors.transparent : t.line)
          : null,
      child: Container(
        constraints: BoxConstraints(minHeight: card ? 56 : 48),
        padding: EdgeInsets.symmetric(horizontal: card ? 12 : 0, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? t.accent : t.fade,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: t.accent,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Type.sans(
                      15,
                      weight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: t.ink,
                    ),
                  ),
                  if (about case final about?)
                    Text(
                      about,
                      style: Type.sans(12.5, color: t.muted, height: 1.4),
                    ),
                ],
              ),
            ),
            if (hint case final hint?)
              Text(hint, style: Type.sans(12.5, color: t.muted)),
          ],
        ),
      ),
    );
  }
}
