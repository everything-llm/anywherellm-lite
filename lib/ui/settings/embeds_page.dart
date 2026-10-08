import 'package:flutter/material.dart';

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
    AppScope.of(context).system.readEmbeds();
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
          children: [
            const PageNote(
              'Visitors ask without a key, so an embed answers only in Chat or Query mode, '
              'never as an agent.',
            ),
            if (system.embedProblem case final problem?) ...[
              const SizedBox(height: 12),
              AlertBox(AlertKind.bad, problem.title, text: problem.text),
            ],
            const SizedBox(height: 16),
            const _NewEmbed(),
            const SizedBox(height: 24),
            if (embeds == null)
              HelpText(
                system.changing ? 'Loading…' : 'The embeds could not be read.',
                status: true,
              )
            else if (embeds.isEmpty)
              const HelpText('No embeds yet.', status: true)
            else
              for (final embed in embeds) ...[
                _EmbedCard(embed, key: ValueKey(embed.uuid)),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }
}

/// The form that makes an embed: its workspace, mode, sites and limits.
class _NewEmbed extends StatefulWidget {
  const _NewEmbed();

  @override
  State<_NewEmbed> createState() => _NewEmbedState();
}

class _NewEmbedState extends State<_NewEmbed> {
  String? _slug;
  EmbedMode _mode = EmbedMode.query;
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

  Future<void> _make() async {
    final slug = _slug;
    if (slug == null) return;
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
      setState(() => _slug = null);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('New embed'),
        const SizedBox(height: 8),
        const HelpText('The workspace it answers from'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final w in workspaces)
              _Pick(
                w.name,
                selected: _slug == w.slug,
                onTap: () => setState(() => _slug = w.slug),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Segmented<EmbedMode>(
          options: [for (final m in EmbedMode.values) (m, m.label)],
          value: _mode,
          onChanged: (m) => setState(() => _mode = m),
        ),
        const SizedBox(height: 12),
        AppField(
          controller: _sites,
          label: 'Sites it answers on',
          hint: 'Sites it answers on, such as example.com; empty for any',
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AppField(
                controller: _perDay,
                label: 'Chats a day',
                hint: 'Chats a day; empty for no limit',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppField(
                controller: _perSession,
                label: 'Chats a visit',
                hint: 'Chats a visit; empty for no limit',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        if (_limitProblem case final problem?) ...[
          const SizedBox(height: 6),
          HelpText(problem, status: true),
        ],
        const SizedBox(height: 10),
        ActionRow([
          AppButton(
            'Make embed',
            primary: true,
            onPressed: _slug == null || changing ? null : _make,
          ),
        ]),
      ],
    );
  }
}

/// A workspace to pick, drawn as a chip that fills when picked.
class _Pick extends StatelessWidget {
  const _Pick(this.name, {required this.selected, required this.onTap});

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: name,
      selected: selected,
      onTap: onTap,
      radius: BorderRadius.circular(99),
      color: selected ? t.accent : t.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          name,
          style: Type.sans(13, color: selected ? t.onaccent : t.ink),
        ),
      ),
    );
  }
}

/// One embed: its workspace, whether it is on, its mode, its HTML, its chats and Delete.
class _EmbedCard extends StatefulWidget {
  const _EmbedCard(this.embed, {super.key});

  final Embed embed;

  @override
  State<_EmbedCard> createState() => _EmbedCardState();
}

class _EmbedCardState extends State<_EmbedCard> {
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  embed.workspace,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(15, weight: FontWeight.w600, color: t.ink),
                ),
              ),
              AppSwitch(
                value: embed.enabled,
                label: 'Embed for ${embed.workspace} on',
                onChanged: changing
                    ? null
                    : (on) => system.setEnabled(embed.uuid, on),
              ),
            ],
          ),
          const SizedBox(height: 4),
          HelpText(
            '${embed.chats == 1 ? '1 chat' : '${embed.chats} chats'} · ${embed.uuid}',
          ),
          const SizedBox(height: 10),
          Segmented<EmbedMode>(
            options: [for (final m in EmbedMode.values) (m, m.label)],
            value: embed.mode,
            onChanged: changing ? null : (m) => system.setMode(embed.uuid, m),
          ),
          if (snippet != null) ...[
            const SizedBox(height: 10),
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
          ],
          const SizedBox(height: 10),
          if (_confirming)
            ConfirmBox(
              text:
                  'Delete the embed for ${embed.workspace}? Pages that carry it stop showing it.',
              onCancel: () => setState(() => _confirming = false),
              onConfirm: () {
                setState(() => _confirming = false);
                system.deleteEmbed(embed.uuid);
              },
            )
          else
            ActionRow([
              AppButton(
                _chats == null ? 'Show chats' : 'Hide chats',
                onPressed: () {
                  final open = _chats == null;
                  setState(() {
                    _chats = open ? system.embedChats(embed.uuid) : null;
                  });
                },
              ),
              AppButton(
                'Delete',
                onPressed: changing
                    ? null
                    : () => setState(() => _confirming = true),
              ),
            ]),
          if (_chats case final chats?) _Chats(chats),
        ],
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
