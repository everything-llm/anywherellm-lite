import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/chat.dart';
import '../../core/connection.dart';
import '../../core/commands.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/tappable.dart';
import 'slash_menu.dart';

/// Where a question is written. Enter sends it and Shift+Enter starts a new line. While this
/// chat answers, Send becomes Stop; while another chat answers, nothing can be sent. Files
/// attached go with the next question only. A message that starts with a slash offers the
/// commands that match it.
class Composer extends StatefulWidget {
  const Composer({super.key, required this.draft, required this.focus});

  final TextEditingController draft;
  final FocusNode focus;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  /// The files picked for the next question.
  List<Attachment> _attached = const [];

  /// Why the last pick added nothing, or null.
  String? _problem;

  /// The command in the menu that Enter picks.
  int _highlight = 0;

  /// Whether Esc closed the menu. It stays closed until the message changes.
  bool _menuClosed = false;

  /// What the form follows besides the message, whose changes [_changed] handles.
  late final Listenable _shown;

  late final AppScope _scope;

  /// The server and the chat on screen, which [_attached] belongs to.
  late Object _chatShown;

  String _typed = '';

  /// Whether the microphone is listening, and what the message held when it began, which what
  /// is heard follows.
  bool _listening = false;
  String _before = '';

  /// Counts the goes, so words that arrive after a message was sent are not put in the next.
  int _go = 0;

  /// Why dictation could not start, or null.
  String? _micProblem;

  @override
  void initState() {
    super.initState();
    final scope = _scope = AppScope.of(context);
    _shown = Listenable.merge([
      scope.settings,
      scope.chat,
      scope.sources.chatMode,
    ]);
    _chatShown = _chatOnScreen();
    _shown.addListener(_chatChanged);
    widget.draft.addListener(_changed);
  }

  @override
  void dispose() {
    _shown.removeListener(_chatChanged);
    widget.draft.removeListener(_changed);
    _go++;
    if (_listening) _scope.dictation?.stop();
    super.dispose();
  }

  /// Starts or ends listening. What is heard follows the message as it stood, and the person
  /// can still edit it.
  Future<void> _dictate() async {
    final dictation = _scope.dictation;
    if (dictation == null) return;
    if (_listening) {
      await dictation.stop();
      return;
    }
    final draft = widget.draft.text;
    _before = draft.isEmpty || draft.endsWith(' ') || draft.endsWith('\n')
        ? draft
        : '$draft ';
    final go = ++_go;
    setState(() {
      _listening = true;
      _micProblem = null;
    });
    final started = await dictation.start(
      onWords: (words) {
        if (go != _go) return;
        _setDraft('$_before$words');
      },
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!started && mounted) {
      setState(() {
        _listening = false;
        _micProblem =
            'Speech recognition is not available, or the microphone is not allowed. '
            "Allow it in Android's settings for the app.";
      });
    }
  }

  /// Puts [text] in the message, with the cursor at its end.
  void _setDraft(String text) => widget.draft.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  Object _chatOnScreen() =>
      (_scope.chat.server, _scope.chat.activeSlug, _scope.chat.activeThread);

  /// Drops the attachments when another chat, workspace or server is shown, so they never go
  /// with a message they were not picked for.
  void _chatChanged() {
    final shown = _chatOnScreen();
    if (shown == _chatShown) return;
    _chatShown = shown;
    if (_attached.isEmpty && _problem == null) return;
    setState(() {
      _attached = const [];
      _problem = null;
    });
  }

  void _changed() {
    if (widget.draft.text == _typed) return;
    setState(() {
      _typed = widget.draft.text;
      _highlight = 0;
      _menuClosed = false;
    });
  }

  /// Puts [command] in the message, ready for the rest of it.
  void _pick(SlashCommand command) {
    _setDraft('${command.command} ');
    widget.focus.requestFocus();
  }

  /// Starts a command in an empty message, which opens the menu.
  void _slash() {
    if (widget.draft.text.isEmpty) {
      widget.draft.value = const TextEditingValue(
        text: '/',
        selection: TextSelection.collapsed(offset: 1),
      );
    }
    setState(() => _menuClosed = false);
    widget.focus.requestFocus();
  }

  /// Attaches the files picked, unless another chat was shown while the picker was open.
  Future<void> _attach() async {
    final shown = _chatShown;
    final List<XFile> picked;
    try {
      picked = await openFiles();
    } catch (error) {
      setState(() => _problem = 'The file picker did not open: $error');
      return;
    }
    final added = <Attachment>[];
    final problems = <String>[];
    for (final file in picked) {
      try {
        final wrong = attachmentProblem(file.name, await file.length());
        if (wrong != null) {
          problems.add(wrong);
          continue;
        }
        added.add(Attachment.of(file.name, await file.readAsBytes()));
      } on Exception {
        problems.add('${file.name} could not be read.');
      }
    }
    if (!mounted || _chatShown != shown) return;
    setState(() {
      _attached = [..._attached, ...added];
      _problem = problems.isEmpty ? null : problems.join(' ');
    });
  }

  void _remove(Attachment attachment) => setState(() {
    _attached = [
      for (final a in _attached)
        if (!identical(a, attachment)) a,
    ];
  });

  /// Sends [text] with the attachments, emptying the composer at once. When nothing was sent,
  /// as when an edit's old exchange could not be deleted, the text and files come back, unless
  /// the person has typed again or another chat shows.
  Future<void> _send(String text) async {
    final attached = _attached;
    final shown = _chatShown;
    widget.draft.clear();
    _go++;
    if (_listening) _scope.dictation?.stop();
    setState(() {
      _attached = const [];
      _problem = null;
      _listening = false;
    });
    final sent = await _scope.chat.send(text, attachments: attached);
    if (sent || !mounted || _chatShown != shown) return;
    if (widget.draft.text.isNotEmpty || _attached.isNotEmpty) return;
    _setDraft(text);
    setState(() => _attached = attached);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final draft = widget.draft;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.column),
          child: ListenableBuilder(
            listenable: _shown,
            builder: (context, _) {
              if (!scope.settings.configured) return const _NoKey();
              final matches = scope.chat.busy || _menuClosed
                  ? const <SlashCommand>[]
                  : commandsFor(draft.text, scope.chat.commands);
              return _Form(
                draft: draft,
                focus: widget.focus,
                attached: _attached,
                problem: _problem,
                matches: matches,
                highlight: matches.isEmpty
                    ? 0
                    : _highlight.clamp(0, matches.length - 1),
                onHighlight: (i) => setState(() => _highlight = i),
                onPick: _pick,
                onDismiss: () => setState(() => _menuClosed = true),
                onSlash: _slash,
                onAttach: _attach,
                onRemove: _remove,
                onSend: _send,
                onDictate: scope.dictation == null ? null : _dictate,
                listening: _listening,
                micProblem: _micProblem,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({
    required this.draft,
    required this.focus,
    required this.attached,
    required this.problem,
    required this.matches,
    required this.highlight,
    required this.onHighlight,
    required this.onPick,
    required this.onDismiss,
    required this.onSlash,
    required this.onAttach,
    required this.onRemove,
    required this.onSend,
    required this.onDictate,
    required this.listening,
    required this.micProblem,
  });

  final TextEditingController draft;
  final FocusNode focus;
  final List<Attachment> attached;
  final String? problem;

  /// The commands that match the message, or none when the menu is closed.
  final List<SlashCommand> matches;
  final int highlight;
  final ValueChanged<int> onHighlight;
  final ValueChanged<SlashCommand> onPick;
  final VoidCallback onDismiss;
  final VoidCallback onSlash;
  final VoidCallback onAttach;
  final ValueChanged<Attachment> onRemove;
  final ValueChanged<String> onSend;

  /// Starts or ends dictation, or null where the device cannot listen.
  final VoidCallback? onDictate;
  final bool listening;

  /// Why dictation could not start, or null.
  final String? micProblem;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final t = Tokens.of(context);
    final here = chat.answeringHere;
    final hint = here
        ? 'Answering…'
        : chat.clearing
        ? 'Clearing the chat…'
        : chat.busy
        ? 'Another chat is still answering…'
        : switch (scope.sources.chatMode.value) {
            ChatMode.automatic || ChatMode.chat => 'Ask anything…',
            ChatMode.query || null => 'Ask about your files…',
          };
    final canSend =
        !chat.busy &&
        chat.ready &&
        chat.active != null &&
        draft.text.trim().isNotEmpty;

    void send() {
      if (canSend) onSend(draft.text);
    }

    /// Enter picks the highlighted command, or sends the message once it is that command.
    void enter() {
      final command = matches[highlight].command;
      if (draft.text.trim().toLowerCase() == command.toLowerCase()) {
        send();
      } else {
        onPick(matches[highlight]);
      }
    }

    final menu = matches.isNotEmpty;
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.enter): menu ? enter : send,
      const SingleActivator(LogicalKeyboardKey.numpadEnter): menu
          ? enter
          : send,
      if (menu) ...{
        const SingleActivator(LogicalKeyboardKey.tab): () =>
            onPick(matches[highlight]),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            onHighlight((highlight + 1) % matches.length),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            onHighlight((highlight - 1) % matches.length),
        const SingleActivator(LogicalKeyboardKey.escape): onDismiss,
      },
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(Sizes.card),
        border: Border.all(color: t.line),
        boxShadow: [
          BoxShadow(
            color: t.shadow.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: t.shadow,
            blurRadius: 24,
            spreadRadius: -12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (problem case final problem?) ...[
            AlertBox(AlertKind.bad, 'Could not attach', text: problem),
            const SizedBox(height: 8),
          ],
          if (micProblem case final problem?) ...[
            AlertBox(AlertKind.bad, 'Could not listen', text: problem),
            const SizedBox(height: 8),
          ],
          if (chat.editing != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Editing a sent message: sending replaces it and everything after it.',
                    style: Type.sans(12, color: t.muted),
                  ),
                ),
                TextAction('close', 'Send as new', chat.cancelEdit),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (menu) ...[
            SlashMenu(
              commands: matches,
              highlight: highlight,
              onPick: onPick,
              note: chat.commandsNote,
            ),
            Divider(height: 13, thickness: 1, color: t.line),
          ],
          if (attached.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in attached)
                  _AttachedChip(a, onRemove: () => onRemove(a)),
              ],
            ),
            const SizedBox(height: 8),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 26, maxHeight: 140),
            child: CallbackShortcuts(
              bindings: bindings,
              child: Semantics(
                label: 'Message',
                textField: true,
                child: TextField(
                  controller: draft,
                  focusNode: focus,
                  enabled: !chat.busy,
                  minLines: 1,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: Type.sans(15.5, color: t.ink, height: 1.5),
                  cursorColor: t.accent,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: Type.sans(15.5, color: t.fade, height: 1.5),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconBtn(
                'attach',
                tooltip: 'Attach files to this message',
                onPressed: chat.busy ? null : onAttach,
                box: 30,
                size: IconSize.small,
              ),
              IconBtn(
                'slash',
                tooltip: 'Commands',
                onPressed: chat.busy ? null : onSlash,
                box: 30,
                size: IconSize.small,
              ),
              const SizedBox(width: 4),
              if (scope.settings.connection case final server?)
                Flexible(
                  child: Tappable(
                    label:
                        'AnythingLLM settings, server ${serverName(server.host)}',
                    tooltip: 'AnythingLLM settings: ${server.baseUrl}',
                    onTap: scope.shell.openSettings,
                    radius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            'settings',
                            size: IconSize.xs,
                            color: t.muted,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              serverName(server.host),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Type.sans(13, color: t.muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              if (onDictate != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconBtn(
                    'mic',
                    tooltip: listening ? 'Stop dictating' : 'Dictate',
                    active: listening,
                    onPressed: chat.busy ? null : onDictate,
                    box: 34,
                    size: IconSize.small,
                  ),
                ),
              if (here)
                _RoundButton(
                  label: 'Stop',
                  color: t.ink,
                  onTap: chat.stop,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: t.bg,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                )
              else
                _RoundButton(
                  label: 'Send',
                  color: canSend ? t.accent : t.off,
                  onTap: canSend ? send : null,
                  child: AppIcon(
                    'send',
                    size: IconSize.small,
                    color: t.onaccent,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A file waiting to go with the next question, with a button that takes it off.
class _AttachedChip extends StatelessWidget {
  const _AttachedChip(this.attachment, {required this.onRemove});

  final Attachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: t.panel2,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: t.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            attachment.isImage ? 'attach' : 'doc',
            size: IconSize.xs,
            color: t.muted,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              attachment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.sans(13, color: t.ink),
            ),
          ),
          IconBtn(
            'close',
            tooltip: 'Remove ${attachment.name}',
            onPressed: onRemove,
            box: 26,
            size: IconSize.xs,
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.label,
    required this.color,
    required this.onTap,
    required this.child,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tappable(
    label: label,
    tooltip: label,
    onTap: onTap,
    radius: BorderRadius.circular(Sizes.control),
    color: color,
    child: SizedBox.square(dimension: 34, child: Center(child: child)),
  );
}

/// In place of the composer until a key is saved.
class _NoKey extends StatelessWidget {
  const _NoKey();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final style = Type.sans(14, color: t.warnfg, height: 1.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: t.warnbg,
        borderRadius: BorderRadius.circular(Sizes.card),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text.rich(
              TextSpan(
                style: style,
                children: [
                  TextSpan(
                    text: 'Not connected yet. ',
                    style: style.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(
                    text: 'Sign in to your AnythingLLM server in Settings to start asking.',
                  ),
                ],
              ),
            ),
          ),
          AppButton(
            'Open Settings',
            primary: true,
            onPressed: scope.shell.openSettings,
          ),
        ],
      ),
    );
  }
}
