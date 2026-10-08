import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/chat.dart';
import '../../core/commands.dart';
import '../../core/prefs.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../settings/settings_pages.dart';
import '../state/chat_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/tappable.dart';
import 'answer_from.dart';
import 'dictation.dart';
import 'model_picker.dart';
import 'slash_menu.dart';

/// Whether [text] can be sent in the chat on screen: nothing runs, the chat is ready, a workspace
/// is open and there is something to send.
bool canSend(ChatController chat, String text) =>
    !chat.busy && chat.ready && chat.active != null && text.trim().isNotEmpty;

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

  /// Whether files are being dragged over the composer.
  bool _over = false;

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

  /// The answer a held message waits for: it goes when that answer ends, however it ends,
  /// while it is still on screen and the message unchanged.
  Turn? _held;

  /// Whether the workspace's chat model picker shows over the field.
  bool _picking = false;

  /// Whether the microphone is listening, and what the message held when it began, which what
  /// is heard follows.
  bool _listening = false;
  String _before = '';

  /// The message as dictation last left it. A message changed from it otherwise, by typing, a
  /// suggestion or Edit, ends the go, so what is heard never overwrites that change.
  String _dictated = '';

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

  /// Starts or ends listening. What is heard follows the message as it stood; a change to the
  /// message made otherwise ends listening.
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
    _dictated = draft;
    setState(() {
      _listening = true;
      _micProblem = null;
    });
    final started = await dictation.start(
      onWords: (words) {
        if (go != _go) return;
        _setDraft(_dictated = '$_before$words');
      },
      onDone: (how) {
        // A go already ended here, by a send or a change to the message, has nothing to end.
        if (!mounted || go != _go) return;
        setState(() => _listening = false);
        final send = _scope.prefs.prefs.isOn(ChatSwitch.sendDictation);
        if (how == DictationEnd.paused &&
            go == _go &&
            send &&
            canSend(_scope.chat, widget.draft.text)) {
          _send(widget.draft.text);
        }
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
  /// with a message they were not picked for. Puts back a message the relay refused because the
  /// chat was already answering, with its files, unless something else was typed meanwhile.
  void _chatChanged() {
    final shown = _chatOnScreen();
    if (shown != _chatShown && (_held != null || _picking)) {
      setState(() {
        _held = null;
        _picking = false;
      });
    }
    _sendHeld();
    if (shown != _chatShown) {
      _chatShown = shown;
      if (_attached.isNotEmpty || _problem != null) {
        setState(() {
          _attached = const [];
          _problem = null;
        });
      }
    }
    if (_scope.chat.takeRefused() case final refused?
        when widget.draft.text.isEmpty && _attached.isEmpty) {
      _setDraft(refused.text);
      setState(() => _attached = refused.attachments);
    }
  }

  void _changed() {
    if (widget.draft.text == _typed) return;
    // Typing more lets go of a held message: what goes is what was held.
    _held = null;
    if (_listening && widget.draft.text != _dictated) {
      _go++;
      _scope.dictation?.stop();
      _listening = false;
    }
    setState(() {
      _typed = widget.draft.text;
      _highlight = 0;
      _menuClosed = false;
    });
  }

  /// Holds the message typed while this chat answers, to go when the answer ends.
  void _hold() {
    final answer = _scope.chat.runningHere;
    if (answer == null || widget.draft.text.trim().isEmpty) return;
    setState(() => _held = answer);
  }

  void _release() => setState(() => _held = null);

  /// Sends the held message once its answer has ended. It waits for the controller to finish
  /// telling everyone, so the chat is no longer busy when it sends.
  void _sendHeld() {
    final held = _held;
    final chat = _scope.chat;
    if (held == null || identical(chat.runningHere, held)) return;
    _held = null;
    if (!chat.turns.contains(held)) return;
    scheduleMicrotask(() {
      if (mounted && canSend(_scope.chat, widget.draft.text)) {
        unawaited(_send(widget.draft.text));
      }
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
    await _addFiles(picked, shown);
  }

  /// Attaches the files dropped on the composer. Nothing is taken while a chat answers, as the
  /// Attach button is off then.
  Future<void> _dropped(DropDoneDetails details) async {
    setState(() => _over = false);
    if (_scope.chat.busy) return;
    await _addFiles(details.files, _chatShown);
  }

  /// Attaches [files], unless another chat than [shown] is on screen once they are read. A file
  /// that is too big, a folder or one that cannot be read is named in [_problem] instead.
  Future<void> _addFiles(List<XFile> files, Object shown) async {
    final added = <Attachment>[];
    final problems = <String>[];
    for (final file in files) {
      if (file is DropItemDirectory) {
        problems.add('${file.name} is a folder; attach the files inside it.');
        continue;
      }
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
    _add(added, problems, shown);
  }

  /// Attaches a picture of type [mime] pasted into the message, unless another chat than
  /// [shown] is on screen by then. Says whether [mime] is a picture a message can carry.
  bool _pasted(Uint8List bytes, String mime, Object shown) {
    final name = pastedImageName(mime, [for (final a in _attached) a.name]);
    if (name == null) return false;
    final wrong = attachmentProblem(name, bytes.length);
    _add([if (wrong == null) Attachment.of(name, bytes)], [?wrong], shown);
    return true;
  }

  void _add(List<Attachment> added, List<String> problems, Object shown) {
    if (!mounted || _chatShown != shown) return;
    setState(() {
      _attached = [..._attached, ...added];
      _problem = problems.isEmpty ? null : problems.join(' ');
    });
  }

  /// Ctrl+V: attaches the picture on the clipboard, or pastes its text when it holds none.
  Future<void> _pasteImage(ImagePaster read, VoidCallback pasteText) async {
    final shown = _chatShown;
    final Uint8List? image;
    try {
      image = await read();
    } on Exception {
      if (mounted) pasteText();
      return;
    }
    if (!mounted) return;
    if (image == null) {
      pasteText();
    } else {
      _pasted(image, 'image/png', shown);
    }
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
              final read = scope.pasteImage;
              final form = DropTarget(
                enable: !scope.chat.busy,
                onDragEntered: (_) => setState(() => _over = true),
                onDragExited: (_) => setState(() => _over = false),
                onDragDone: _dropped,
                child: _Form(
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
                  held: _held != null,
                  onHold: _hold,
                  onRelease: _release,
                  picking: _picking,
                  onPickModel: () => setState(() => _picking = !_picking),
                  onDictate: scope.dictation == null ? null : _dictate,
                  listening: _listening,
                  micProblem: _micProblem,
                  over: _over,
                  onPaste: read == null
                      ? null
                      : (pasteText) => _pasteImage(read, pasteText),
                  onInserted: (content) => switch (content.data) {
                    final bytes? => _pasted(
                      bytes,
                      content.mimeType,
                      _chatShown,
                    ),
                    null => false,
                  },
                ),
              );
              if (!scope.chat.alreadyAnswering) return form;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _AlreadyAnswering(),
                  const SizedBox(height: 8),
                  form,
                ],
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
    required this.held,
    required this.onHold,
    required this.onRelease,
    required this.picking,
    required this.onPickModel,
    required this.onDictate,
    required this.listening,
    required this.micProblem,
    required this.over,
    required this.onPaste,
    required this.onInserted,
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

  /// Whether the message waits for the answer running here to end.
  final bool held;
  final VoidCallback onHold;
  final VoidCallback onRelease;

  /// Whether the workspace's chat model picker shows, which [onPickModel] opens and closes.
  final bool picking;
  final VoidCallback onPickModel;

  /// Starts or ends dictation, or null where the device cannot listen.
  final VoidCallback? onDictate;
  final bool listening;

  /// Why dictation could not start, or null.
  final String? micProblem;

  /// Whether files are being dragged over the composer, which lights its edge.
  final bool over;

  /// Ctrl+V, given the field's own paste of text, or null where the platform's paste is left
  /// as it is.
  final void Function(VoidCallback pasteText)? onPaste;

  /// Attaches content a phone's keyboard inserts, such as a copied picture. Says whether it
  /// was a picture a message can carry.
  final bool Function(KeyboardInsertedContent content) onInserted;

  /// The message [field], with Ctrl+V handed to [onPaste] when there is one.
  Widget _pasting(Widget field) => switch (onPaste) {
    final onPaste? => Actions(
      actions: {PasteTextIntent: _PasteImage(onPaste)},
      child: field,
    ),
    null => field,
  };

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
    final sendable = canSend(chat, draft.text);

    void send() {
      if (sendable) onSend(draft.text);
    }

    // While this chat answers, a message typed is held to go when the answer ends. Send when
    // done takes the chips' room, as they are off while the chat answers.
    final holdable = here && !held && draft.text.trim().isNotEmpty;
    final phone = ScreenClass.ofContext(context).isPhone;

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
    final VoidCallback onEnter = menu
        ? enter
        : here
        ? onHold
        : send;
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.enter): onEnter,
      const SingleActivator(LogicalKeyboardKey.numpadEnter): onEnter,
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

    return AnswerFromAnchor(
      onPickModel: () {
        if (!picking) onPickModel();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(Sizes.card),
          border: Border.all(color: over ? t.accent : t.line),
          boxShadow: [
            BoxShadow(
              color: t.shadow,
              // Flutter blurs a radius more than CSS does; 20 here is CSS's 24.
              blurRadius: 20,
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
            if (chat.editing != null)
              _FormNote(
                'Editing a sent message: sending replaces it and everything after it.',
                action: 'Send as new',
                onAction: chat.cancelEdit,
              ),
            if (held)
              _FormNote(
                'Sends when this answer ends.',
                action: "Don't send",
                onAction: onRelease,
              ),
            if (picking) ...[
              ModelPicker(onClose: onPickModel),
              Divider(height: 21, thickness: 1, color: t.line),
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
                  // Only the field follows the prefs, for its spellcheck.
                  child: ListenableBuilder(
                    listenable: scope.prefs,
                    builder: (context, _) => _pasting(
                      TextField(
                        controller: draft,
                        focusNode: focus,
                        // Open while this chat answers, for the next message.
                        enabled: !chat.busy || here,
                        spellCheckConfiguration:
                            scope.canSpellcheck &&
                                scope.prefs.prefs.isOn(ChatSwitch.spellcheck)
                            ? const SpellCheckConfiguration()
                            : const SpellCheckConfiguration.disabled(),
                        minLines: 1,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        // A phone's keyboard starts each sentence with a capital.
                        textCapitalization: TextCapitalization.sentences,
                        style: Type.sans(15.5, color: t.ink, height: 1.5),
                        cursorColor: t.accent,
                        // A picture from a phone keyboard's clipboard; the rest goes in as text.
                        contentInsertionConfiguration:
                            ContentInsertionConfiguration(
                              allowedMimeTypes: imageMimes.toList(),
                              onContentInserted: onInserted,
                            ),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: hint,
                          hintStyle: Type.sans(
                            15.5,
                            color: t.fade,
                            height: 1.5,
                          ),
                        ),
                      ),
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
                // Takes all the room left, so Send sits at the right edge. On a phone the model is
                // a row in the Answer from menu, since the row has room for one chip.
                Expanded(
                  child: holdable
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: _SendWhenDone(onTap: onHold),
                        )
                      : Row(
                          children: [
                            const Flexible(child: AnswerFromChip()),
                            if (!phone) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: ModelChip(
                                  open: picking,
                                  onTap: onPickModel,
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
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
                if (holdable) const SizedBox(width: 8),
                if (here)
                  _RoundButton(
                    label: 'Stop the answer',
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
                    color: sendable ? t.accent : t.off,
                    onTap: sendable ? send : null,
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
      ),
    );
  }
}

/// Paste in the message field, which hands [onPaste] the field's own paste of text, for a
/// clipboard that holds no picture.
class _PasteImage extends ContextAction<PasteTextIntent> {
  _PasteImage(this.onPaste);

  final void Function(VoidCallback pasteText) onPaste;

  @override
  bool isEnabled(PasteTextIntent intent, [BuildContext? context]) =>
      callingAction?.isEnabled(intent) ?? true;

  @override
  Object? invoke(PasteTextIntent intent, [BuildContext? context]) {
    // The field's own paste is known only while this runs.
    final own = callingAction;
    onPaste(() => own?.invoke(intent));
    return null;
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
          if (attachment.isImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(
                attachment.bytes,
                width: 22,
                height: 22,
                fit: BoxFit.cover,
                cacheWidth: (22 * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) =>
                    AppIcon('attach', size: IconSize.xs, color: t.muted),
              ),
            )
          else
            AppIcon('doc', size: IconSize.xs, color: t.muted),
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
    touchTarget: true,
    label: label,
    tooltip: label,
    onTap: onTap,
    radius: BorderRadius.circular(Sizes.control),
    color: color,
    child: SizedBox.square(dimension: 34, child: Center(child: child)),
  );
}

/// A line over the field about the message, with the [action] that undoes it.
class _FormNote extends StatelessWidget {
  const _FormNote(this.text, {required this.action, required this.onAction});

  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: Type.sans(12, color: Tokens.of(context).muted),
          ),
        ),
        TextAction('close', action, onAction),
      ],
    ),
  );
}

/// Holds the message typed while this chat answers, to go when the answer ends. There is no
/// Send now: the relay runs one answer a chat.
class _SendWhenDone extends StatelessWidget {
  const _SendWhenDone({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      touchTarget: true,
      label: 'Send when done',
      tooltip: 'Send when done',
      onTap: onTap,
      radius: BorderRadius.circular(Sizes.control),
      color: t.accentbg,
      child: SizedBox(
        height: 34,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            widthFactor: 1,
            child: Text(
              'Send when done',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.sans(13.5, weight: FontWeight.w500, color: t.accent),
            ),
          ),
        ),
      ),
    );
  }
}

/// Over the composer while the chat on screen answers a message sent elsewhere, after the relay
/// refused the one sent here.
class _AlreadyAnswering extends StatelessWidget {
  const _AlreadyAnswering();

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    child: const AlertBox(
      AlertKind.warn,
      'This chat is still answering, maybe on another device. Send when it ends, or stop it.',
      plain: true,
    ),
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
            onPressed: () => scope.shell.openSettings(SettingsPage.connection),
          ),
        ],
      ),
    );
  }
}
