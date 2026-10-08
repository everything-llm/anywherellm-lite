import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../../core/embeds.dart';
import '../app_scope.dart';
import '../chat/answer_body.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/confirm_box.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import '../widgets/segmented.dart';
import '../widgets/tappable.dart';
import 'rows.dart';

/// The server's chat embeds: a chat box for one workspace that a web page carries. Each can be
/// turned off, answer in another mode, give its HTML, show its chats or be deleted.
class EmbedsPage extends StatefulWidget {
  const EmbedsPage({super.key});

  @override
  State<EmbedsPage> createState() => _EmbedsPageState();
}

class _EmbedsPageState extends State<EmbedsPage> {
  @override
  void initState() {
    super.initState();
    // After the frame: the read tells its listeners at once, and some are built elsewhere.
    final system = AppScope.of(context).system;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) system.readEmbeds();
    });
  }

  @override
  Widget build(BuildContext context) {
    final system = AppScope.of(context).system;
    return ListenableBuilder(
      listenable: system,
      builder: (context, _) {
        final embeds = system.embeds;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 20,
          children: [
            if (system.embedProblem case final problem?)
              AlertBox(AlertKind.bad, problem.title, text: problem.text),
            if (embeds == null)
              HelpText(
                system.changing ? 'Loading…' : 'The embeds could not be read.',
                status: true,
              )
            else
              LayoutBuilder(
                builder: (context, box) {
                  final wide = box.maxWidth >= _EmbedRow.columnsFrom;
                  return FieldCard([
                    if (wide) const _Columns(),
                    if (embeds.isEmpty)
                      const _NoEmbeds()
                    else
                      for (final embed in embeds)
                        _EmbedRow(embed, wide: wide, key: ValueKey(embed.uuid)),
                  ]);
                },
              ),
            const _NewEmbed(),
          ],
        );
      },
    );
  }
}

/// The names of the columns over the embeds, where they show side by side.
class _Columns extends StatelessWidget {
  const _Columns();

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        spacing: _EmbedRow.gap,
        children: [
          Expanded(child: SectionLabel('Workspace', header: false)),
          SizedBox(
            width: _EmbedRow.modeWidth,
            child: SectionLabel('Mode', header: false),
          ),
          SizedBox(
            width: _EmbedRow.chatsWidth,
            child: SectionLabel('Chats', header: false),
          ),
          SizedBox(
            width: _EmbedRow.onWidth,
            child: SectionLabel('On', header: false),
          ),
          SizedBox(width: _EmbedRow.actionsWidth),
        ],
      ),
    ),
  );
}

class _NoEmbeds extends StatelessWidget {
  const _NoEmbeds();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
    child: Text(
      'No embeds yet.',
      textAlign: TextAlign.center,
      style: Type.sans(13.5, color: Tokens.of(context).muted),
    ),
  );
}

/// The form that makes an embed: its workspace, mode, sites and limits.
class _NewEmbed extends StatefulWidget {
  const _NewEmbed();

  @override
  State<_NewEmbed> createState() => _NewEmbedState();
}

class _NewEmbedState extends State<_NewEmbed> {
  /// The workspace picked, or null for the first.
  String? _slug;
  EmbedMode _mode = EmbedMode.chat;
  final _sites = TextEditingController();
  final _perDay = TextEditingController();
  final _perSession = TextEditingController();

  /// Why a limit was not taken, or null.
  String? _limitProblem;

  @override
  void dispose() {
    _sites.dispose();
    _perDay.dispose();
    _perSession.dispose();
    super.dispose();
  }

  Future<void> _make(String slug) async {
    if (!_isLimit(_perDay.text) || !_isLimit(_perSession.text)) {
      setState(
        () => _limitProblem =
            'A limit is a whole number above 0, or empty for no limit.',
      );
      return;
    }
    setState(() => _limitProblem = null);
    final made = await AppScope.of(context).system.createEmbed(
      NewEmbed(
        workspaceSlug: slug,
        mode: _mode,
        sites: sitesOf(_sites.text),
        chatsPerDay: _count(_perDay.text),
        chatsPerSession: _count(_perSession.text),
      ),
    );
    if (made && mounted) {
      _sites.clear();
      _perDay.clear();
      _perSession.clear();
    }
  }

  /// Whether [text] is a limit: empty for none, or a whole number above nought. A limit cannot
  /// be changed once the embed is made, so a mistyped one is refused rather than dropped.
  static bool _isLimit(String text) =>
      text.trim().isEmpty || (int.tryParse(text.trim()) ?? 0) > 0;

  /// [text] as a limit, or null for none.
  int? _count(String text) => int.tryParse(text.trim());

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    // Follows the workspaces, which may load after the page opens, and whether an embed is
    // being changed.
    return ListenableBuilder(
      listenable: Listenable.merge([scope.chat, scope.system]),
      builder: _form,
    );
  }

  Widget _form(BuildContext context, Widget? _) {
    final scope = AppScope.of(context);
    final workspaces = scope.chat.workspaces;
    final changing = scope.system.changing;
    final names = {for (final w in workspaces) w.slug: w.name};
    final slug = names.containsKey(_slug)
        ? _slug
        : workspaces.firstOrNull?.slug;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 20,
      children: [
        const SubHead('New embed'),
        FieldCard([
          FieldRow(
            label: 'Workspace',
            control: Semantics(
              label: 'Workspace',
              child: AppSelect(
                value: slug,
                choices: [for (final w in workspaces) w.slug],
                labelOf: (s) => names[s] ?? s,
                onChanged: (s) => setState(() => _slug = s),
              ),
            ),
          ),
          FieldRow(
            label: 'Answers',
            help: 'Query answers only from documents.',
            control: Segmented<EmbedMode>(
              options: [for (final m in EmbedMode.values) (m, m.label)],
              value: _mode,
              onChanged: (m) => setState(() => _mode = m),
            ),
          ),
          FieldRow(
            label: 'Allowed sites',
            help: 'Comma-separated. Empty allows any site.',
            control: AppField(
              controller: _sites,
              label: 'Allowed sites',
              hint: 'example.com',
              keyboardType: TextInputType.url,
            ),
          ),
          FieldRow(
            label: 'Chats per day',
            help: 'Empty means no limit.',
            control: AppField(
              controller: _perDay,
              label: 'Chats per day',
              hint: 'No limit',
              keyboardType: TextInputType.number,
            ),
          ),
          FieldRow(
            label: 'Chats per visit',
            help: 'Empty means no limit.',
            control: AppField(
              controller: _perSession,
              label: 'Chats per visit',
              hint: 'No limit',
              keyboardType: TextInputType.number,
            ),
          ),
        ]),
        const PageNote(
          'Allowed sites and limits are set when the embed is made and cannot be changed '
          'after.',
        ),
        if (_limitProblem case final problem?) HelpText(problem, status: true),
        ActionRow(alignment: WrapAlignment.start, [
          AppButton(
            'Create embed',
            primary: true,
            onPressed: slug == null || changing ? null : () => _make(slug),
          ),
        ]),
      ],
    );
  }
}

/// One embed: its workspace, mode, chats and whether it is on, in columns when [wide], and its
/// HTML, its chats and Delete, each opening under it.
class _EmbedRow extends StatefulWidget {
  const _EmbedRow(this.embed, {super.key, required this.wide});

  final Embed embed;
  final bool wide;

  /// The least width of the list with its columns side by side.
  static const columnsFrom = 600.0;

  static const gap = 12.0;
  static const modeWidth = 110.0;
  static const chatsWidth = 56.0;
  static const onWidth = 52.0;
  static const actionsWidth = 200.0;

  @override
  State<_EmbedRow> createState() => _EmbedRowState();
}

class _EmbedRowState extends State<_EmbedRow> {
  bool _showHtml = false;
  bool _confirming = false;
  Future<List<EmbedChat>?>? _chats;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final system = scope.system;
    final t = Tokens.of(context);
    final embed = widget.embed;
    final changing = system.changing;
    final server = scope.settings.connection?.uri;
    final snippet = server == null ? null : embedSnippet(server, embed.uuid);
    final name = Text(
      embed.workspace,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Type.sans(14, weight: FontWeight.w500, color: t.ink),
    );
    final chats = plural(embed.chats, 'chat', 'chats');
    final on = AppSwitch(
      value: embed.enabled,
      large: true,
      label: 'Embed for ${embed.workspace} on',
      onChanged: changing ? null : (on) => system.setEnabled(embed.uuid, on),
    );
    final mode = Semantics(
      label: 'Mode of the embed for ${embed.workspace}',
      child: AppSelect(
        value: embed.mode.name,
        choices: [for (final m in EmbedMode.values) m.name],
        labelOf: (m) => EmbedMode.fromServer(m).label,
        onChanged: changing
            ? null
            : (m) => system.setMode(embed.uuid, EmbedMode.fromServer(m)),
      ),
    );
    final actions = Wrap(
      alignment: widget.wide ? WrapAlignment.end : WrapAlignment.start,
      spacing: 4,
      runSpacing: 4,
      children: [
        if (snippet != null)
          _SmallButton(
            'HTML',
            open: _showHtml,
            onTap: () => setState(() => _showHtml = !_showHtml),
          ),
        _SmallButton(
          'Chats',
          open: _chats != null,
          onTap: () => setState(() {
            _chats = _chats == null ? system.embedChats(embed.uuid) : null;
          }),
        ),
        _SmallButton(
          'Delete',
          onTap: changing ? null : () => setState(() => _confirming = true),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          if (widget.wide)
            Row(
              spacing: _EmbedRow.gap,
              children: [
                Expanded(child: name),
                SizedBox(width: _EmbedRow.modeWidth, child: mode),
                SizedBox(
                  width: _EmbedRow.chatsWidth,
                  child: Text(
                    '${embed.chats}',
                    style: Type.sans(13.5, color: t.ink, height: 1.45),
                  ),
                ),
                SizedBox(
                  width: _EmbedRow.onWidth,
                  child: Align(alignment: Alignment.centerLeft, child: on),
                ),
                SizedBox(width: _EmbedRow.actionsWidth, child: actions),
              ],
            )
          else ...[
            Row(
              spacing: 12,
              children: [
                Expanded(child: name),
                on,
              ],
            ),
            HelpText(chats),
            mode,
            actions,
          ],
          if (_showHtml && snippet != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    snippet,
                    style: Type.mono(12, color: t.ink2, height: 1.45),
                  ),
                ),
                CopyButton(snippet, tooltip: 'Copy the HTML'),
              ],
            ),
          if (_chats case final chats?) _Chats(chats),
          if (_confirming)
            ConfirmBox(
              text:
                  'Delete the embed for ${embed.workspace}? Pages that carry it stop showing it.',
              onCancel: () => setState(() => _confirming = false),
              onConfirm: () {
                setState(() => _confirming = false);
                system.deleteEmbed(embed.uuid);
              },
            ),
        ],
      ),
    );
  }
}

/// A small bordered button in an embed's row; [open] marks one that shows something under the
/// row while it does.
class _SmallButton extends StatelessWidget {
  const _SmallButton(this.label, {required this.onTap, this.open});

  final String label;
  final VoidCallback? onTap;
  final bool? open;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: label,
      onTap: onTap,
      toggled: open,
      touchTarget: true,
      radius: BorderRadius.circular(8),
      color: open == true ? t.sel : t.panel,
      side: BorderSide(color: t.line),
      dimWhenDisabled: 0.5,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            widthFactor: 1,
            child: Text(label, style: Type.sans(12.5, color: t.ink)),
          ),
        ),
      ),
    );
  }
}

/// The chats an embed has held, each a question and its answer.
class _Chats extends StatelessWidget {
  const _Chats(this.chats);

  final Future<List<EmbedChat>?> chats;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return FutureBuilder(
      future: chats,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const HelpText('Loading…', status: true);
        }
        final list = snapshot.data;
        if (list == null) return const SizedBox.shrink();
        if (list.isEmpty) return const HelpText('No chats yet.', status: true);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final chat in list)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chat.question,
                      style: Type.sans(
                        14,
                        weight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(chat.answer, style: Type.sans(14, color: t.ink2)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
