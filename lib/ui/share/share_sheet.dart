import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../../core/outputs.dart';
import '../../core/upload.dart';
import '../sources/sources_panel.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../settings/rows.dart';
import '../settings/settings_pages.dart';
import '../state/shell_controller.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/sheet.dart';
import '../widgets/tappable.dart';
import 'shared_item.dart';

/// [bytes] as they are when they are already a [Uint8List], copied otherwise.
Uint8List _bytesOf(List<int> bytes) =>
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

/// The bytes of a shared file, or [UnreadableFile] when it cannot be read, as a revoked
/// permission or a file deleted since it was shared would leave it.
Future<List<int>> _readShared(Future<List<int>> Function() read) async {
  try {
    return await read();
  } on Exception {
    throw const UnreadableFile('The shared file could not be read.');
  }
}

/// What to do with a shared item.
enum _Use { add, ask }

/// Share to AnywhereLLM Lite: what another app shared, the workspace to take it (the open one first,
/// and chosen), then Add to documents, which adds it to that workspace's documents, or Ask about
/// it, which opens a new chat there with it in the message, a file attached, for the person to
/// ask. With no server saved it says to connect first.
class ShareSheet extends StatefulWidget {
  const ShareSheet(this.item, {super.key});

  final SharedItem item;

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  late String? _slug = AppScope.of(context).chat.activeSlug;
  bool _working = false;
  String? _problem;

  /// The item's tile, name and the line under it.
  (String, String, String) get _shown => switch (widget.item) {
    SharedLink(:final url, :final title) => (
      'WEB',
      title ?? url.host,
      '${url.host}${url.path == '/' ? '' : url.path}',
    ),
    SharedText(:final text) => ('TXT', 'Text you selected', text),
    SharedFile(:final name, :final size) => (
      sourceExt(name),
      name,
      '${sourceExt(name)} · ${sizeText(size)}',
    ),
  };

  Future<void> _go(_Use use) async {
    final scope = AppScope.of(context);
    final slug = _slug;
    if (slug == null) return;
    final item = widget.item;
    if (item case SharedFile(:final name, :final size)
        when use == _Use.ask && size > maxAttachmentBytes) {
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
    try {
      switch (use) {
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
              await sources.upload([
                UploadFile(name: name, read: () => _readShared(read)),
              ]);
          }
          shell
            ..closeShared()
            ..openSources();
        case _Use.ask:
          final (message, attachments) = switch (item) {
            SharedLink(:final url) => ('$url\n\n', const <Attachment>[]),
            SharedText(:final text) => (
              '> ${text.trim().replaceAll('\n', '\n> ')}\n\n',
              const <Attachment>[],
            ),
            SharedFile(:final name, :final read) => (
              '',
              [Attachment.of(name, _bytesOf(await _readShared(read)))],
            ),
          };
          chat.newChat();
          shell
            ..closeShared()
            ..openChat();
          chat.putInComposer(message, attachments);
      }
    } on UnreadableFile catch (error) {
      if (mounted) {
        setState(() {
          _working = false;
          _problem = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final shell = scope.shell;
    final (tile, name, about) = _shown;
    return SheetFrame(
      title: 'Share to AnywhereLLM Lite',
      onClose: shell.closeShared,
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
              spacing: 16,
              children: [
                FieldCard([
                  Container(
                    constraints: const BoxConstraints(minHeight: Sizes.cardRow),
                    padding: const EdgeInsets.symmetric(
                      horizontal: FieldCard.inset,
                      vertical: 10,
                    ),
                    child: Row(
                      spacing: 14,
                      children: [
                        TypeTile.label(tile),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Type.sans(17, color: t.ink),
                              ),
                              Text(
                                about,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Type.sans(13, color: t.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
                if (!scope.settings.configured) ...[
                  const HelpText(
                    'Connect to your AnythingLLM server first, then share it again.',
                  ),
                  ActionRow(even: true, [
                    AppButton(
                      'Open Settings',
                      primary: true,
                      onPressed: () {
                        shell.closeShared();
                        shell.openSettings(SettingsPage.connection);
                      },
                    ),
                  ]),
                ] else ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 12,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: SectionLabel('Workspace'),
                      ),
                      FieldCard([
                        for (final w in workspaces)
                          _WorkspaceRow(
                            w.name,
                            chosen: w == chosen,
                            onTap: () => setState(() => _slug = w.slug),
                          ),
                      ]),
                    ],
                  ),
                  if (_problem case final problem?)
                    HelpText(problem, status: true),
                  ActionRow(even: true, [
                    AppButton(
                      'Add to documents',
                      onPressed: _working || chosen == null
                          ? null
                          : () => _go(_Use.add),
                    ),
                    AppButton(
                      'Ask about it',
                      primary: true,
                      onPressed: _working || chosen == null
                          ? null
                          : () => _go(_Use.ask),
                    ),
                  ]),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A workspace that can take the item, checked while [chosen].
class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow(this.name, {required this.chosen, required this.onTap});

  final String name;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: chosen,
      child: Tappable(
        label: name,
        selected: chosen,
        onTap: onTap,
        excludeSemantics: false,
        child: Container(
          constraints: const BoxConstraints(minHeight: Sizes.cardRow),
          padding: const EdgeInsets.symmetric(horizontal: FieldCard.inset),
          child: Row(
            spacing: 14,
            children: [
              SizedBox.square(
                dimension: IconSize.row.px,
                child: chosen
                    ? AppIcon('check', size: IconSize.row, color: t.ink)
                    : null,
              ),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(
                    17,
                    weight: chosen ? FontWeight.w600 : FontWeight.w400,
                    color: t.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
