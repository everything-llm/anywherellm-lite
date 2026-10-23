import 'dart:async';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/chat.dart';
import '../../core/copy.dart';
import '../../core/prefs.dart';
import '../../core/shortcuts.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../settings/settings_pages.dart';
import '../settings/rows.dart';
import '../shell_popup.dart';
import '../state/chat_controller.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/rise.dart';
import '../widgets/tappable.dart';
import '../widgets/segmented.dart';
import 'answer_from.dart';
import 'attach_sheet.dart';
import 'dictation.dart';
import 'model_picker.dart';
import 'shortcut_chip.dart';

/// Where a question is written. On a desktop ([AppScope.enterSends]) Enter sends it and
/// Shift+Enter starts a new line; on a phone Enter starts a new line and Send sends. While this
/// chat answers, Send becomes Send when done while something is typed, and Stop while nothing
/// is. Files attached go with the next question only.
class Composer extends StatefulWidget {
  const Composer({super.key, required this.draft, required this.focus});

  final TextEditingController draft;
  final FocusNode focus;

  @override
  State<Composer> createState() => ComposerState();
}

/// What the [Composer] holds.
class ComposerState extends State<Composer> {
  /// The files picked for the next question.
  List<Attachment> _attached = const [];

  PromptShortcut? _shortcut;
  bool _shortcutsTab = false;

  /// Whether the person is being asked to confirm clearing the chat.
  bool _asking = false;

  /// Why the last pick added nothing, or null.
  String? _problem;

  /// What the form follows besides the message, whose changes [_changed] handles.
  late final Listenable _shown;

  late final AppScope _scope;

  /// The server and the chat on screen, which [_attached] belongs to.
  late Object _chatShown;

  String _typed = '';

  /// Whether the workspace's chat model picker shows over the field.
  bool _picking = false;

  /// Whether the microphone is listening, and what the message held when it began, which what
  /// is heard follows.
  bool _listening = false;
  String _before = '';

  /// The message as dictation last left it. A message changed from it otherwise, by typing, a
  /// shortcut or Edit, ends the go, so what is heard never overwrites that change.
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
    var heard = false;
    setState(() {
      _listening = true;
      _micProblem = null;
    });
    final started = await dictation.start(
      onWords: (words) {
        if (go != _go) return;
        if (words.trim().isNotEmpty) heard = true;
        _setDraft(_dictated = '$_before$words');
      },
      onDone: (how) {
        // A go already ended here, by a send or a change to the message, has nothing to end.
        if (!mounted || go != _go) return;
        setState(() => _listening = false);
        final send = _scope.prefs.prefs.isOn(ChatSwitch.sendDictation);
        // A pause that heard nothing leaves what was typed to the person, not to a send.
        if (how == DictationEnd.paused &&
            heard &&
            send &&
            _scope.chat.canSend(widget.draft.text)) {
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

  /// Puts [text] back as the message to send as a new one, without the shortcut chosen for
  /// the one it replaces, since [text] may already be what that shortcut expanded to.
  void edit(String text) {
    if (_shortcut != null) setState(() => _shortcut = null);
    _setDraft(text);
    widget.focus.requestFocus();
  }

  /// Puts [item], a message waiting in this chat, back in the message to write again: its words
  /// ahead of what is typed and its files ahead of those attached. Like [edit], it drops the
  /// shortcut chosen, since its words are what a shortcut expanded to.
  void putBack(OnDeck item) {
    if (!_scope.chat.dropOnDeck(item)) return;
    final typed = widget.draft.text;
    setState(() {
      _shortcut = null;
      _attached = [...item.attachments, ..._attached];
    });
    _setDraft(typed.trim().isEmpty ? item.text : '${item.text}\n$typed');
    widget.focus.requestFocus();
  }

  /// Puts [text] in the message, with the cursor at its end.
  void _setDraft(String text) => widget.draft.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  Object _chatOnScreen() =>
      (_scope.chat.server, _scope.chat.activeSlug, _scope.chat.activeThread);

  /// Drops the attachments when another chat, workspace or server is shown, so they never go
  /// with a message they were not picked for. Puts in what another app shared, with its files,
  /// unless something else was typed meanwhile.
  void _chatChanged() {
    final shown = _chatOnScreen();
    if (shown != _chatShown) {
      _chatShown = shown;
      if (_picking ||
          _shortcut != null ||
          _asking ||
          _attached.isNotEmpty ||
          _problem != null) {
        setState(() {
          _picking = false;
          _shortcut = null;
          _asking = false;
          _attached = const [];
          _problem = null;
        });
      }
    }
    // Taken only when it can go back: a message taken and not put back would be lost.
    if (widget.draft.text.isEmpty && _attached.isEmpty) {
      if (_scope.chat.takeForComposer() case final back?) {
        _setDraft(back.text);
        setState(() => _attached = back.attachments);
        widget.focus.requestFocus();
      }
    }
  }

  /// `/name ` and what follows it, which turns the name into a chip.
  static final _typedShortcut = RegExp(
    r'^/([a-z0-9-]+)\s([\s\S]*)$',
    caseSensitive: false,
  );

  void _changed() {
    if (widget.draft.text == _typed) return;
    if (_shortcut == null && widget.draft.text.startsWith('/')) {
      final match = _typedShortcut.firstMatch(widget.draft.text);
      if (match != null) {
        final shortcut = _scope.prefs
            .shortcutsIn(_scope.chat.activeSlug)
            .where((item) => item.answersTo(match[1]!.toLowerCase()))
            .firstOrNull;
        if (shortcut != null) {
          // Shown even when the rest is empty, which leaves the message as it was.
          setState(() => _shortcut = shortcut);
          _setDraft(match[2] ?? '');
          return;
        }
      }
    }
    if (_listening && widget.draft.text != _dictated) {
      _go++;
      _scope.dictation?.stop();
      _listening = false;
    }
    setState(() => _typed = widget.draft.text);
  }

  /// Puts the message typed while this chat answers, with its files, after the messages waiting
  /// in it, emptying the composer for the next.
  void _hold() {
    final (message, use) = _outgoing(widget.draft.text);
    if (message.trim().isEmpty) return;
    final sent = _scope.chat.sendWhenDone(
      message,
      shortcutUse: use,
      attachments: _attached,
      mode: _scope.sources.chatMode.value,
    );
    if (sent) _empty();
  }

  /// Empties the composer once its message has gone: the words, the files, the shortcut, and a
  /// go of dictation, whose later words would land in the next message.
  void _empty() {
    widget.draft.clear();
    _go++;
    if (_listening) _scope.dictation?.stop();
    setState(() {
      _attached = const [];
      _problem = null;
      _listening = false;
      _shortcut = null;
    });
  }

  /// The message [text] sends, with the shortcut it was sent with; empty when the shortcut
  /// needs a detail and has none.
  (String, ShortcutUse?) _outgoing(String text) {
    final shortcut = _shortcut;
    if (shortcut == null) return (text, null);
    if (shortcut.requiresDetail && text.trim().isEmpty) return ('', null);
    return (
      shortcut.expand(text),
      ShortcutUse(label: shortcut.label, detail: text.trim()),
    );
  }

  /// Attaches the files picked, unless another chat was shown while the picker was open.
  Future<void> _attach() => _pickWith(
    () async => [for (final f in await FilePicker.pickFiles()) f.xFile],
    'The file picker did not open',
  );

  /// Attaches what [pick] gives, unless another chat was shown meanwhile. A failure is put in
  /// [_problem] after [failed].
  Future<void> _pickWith(
    Future<List<XFile>> Function() pick,
    String failed,
  ) async {
    final shown = _chatShown;
    final List<XFile> picked;
    try {
      picked = await pick();
    } catch (error) {
      if (mounted) setState(() => _problem = '$failed: $error');
      return;
    }
    await _addFiles(picked, shown);
  }

  /// The Attach sheet, over the composer while [Popup.attach] is open.
  Widget _attachSheet(Widget child) {
    final shell = _scope.shell;
    final photos = _scope.photos;
    return ShellPopup(
      popup: Popup.attach,
      title: 'Add to your message',
      builder: (context, close) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Segmented<bool>(
            options: const [(false, 'Attach'), (true, 'Shortcuts')],
            value: _shortcutsTab,
            onChanged: (show) => setState(() => _shortcutsTab = show),
          ),
          AnimatedSize(
            duration: motion(context, const Duration(milliseconds: 180)),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _shortcutsTab
                ? _ShortcutPicker(
                    onSelect: _selectShortcut,
                    onManage: () {
                      close();
                      shell.openSettings(SettingsPage.shortcuts);
                    },
                  )
                : AttachSheet(
                    attached: _attached,
                    onRemove: _remove,
                    onPhotos: photos == null
                        ? null
                        : () => _pickWith(
                            photos.choose,
                            'The photos did not open',
                          ),
                    onCamera: photos == null
                        ? null
                        : () => _pickWith(
                            () async => [?await photos.take()],
                            'The camera did not open',
                          ),
                    onFiles: _attach,
                    onDone: close,
                  ),
          ),
        ],
      ),
      child: child,
    );
  }

  /// Attaches [files], unless another chat than [shown] is on screen once they are read. A file
  /// that is too big or cannot be read is named in [_problem] instead.
  Future<void> _addFiles(List<XFile> files, Object shown) async {
    final added = <Attachment>[];
    final problems = <String>[];
    for (final file in files) {
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

  /// Attaches a picture of type [mime] pasted into the message. Says whether [mime] is a
  /// picture a message can carry.
  bool _pasted(Uint8List bytes, String mime) {
    final name = pastedImageName(mime, [for (final a in _attached) a.name]);
    if (name == null) return false;
    final wrong = attachmentProblem(name, bytes.length);
    _add([if (wrong == null) Attachment.of(name, bytes)], [?wrong], _chatShown);
    return true;
  }

  void _add(List<Attachment> added, List<String> problems, Object shown) {
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
    final shortcut = _shortcut;
    if (shortcut == null && _scope.chat.canReset && isResetCommand(text)) {
      return _askReset();
    }
    final (message, use) = _outgoing(text);
    if (message.trim().isEmpty) return;
    final attached = _attached;
    final shown = _chatShown;
    _empty();
    final sent = await _scope.chat.send(
      message,
      attachments: attached,
      mode: _scope.sources.chatMode.value,
      shortcutUse: use,
    );
    if (sent || !mounted || _chatShown != shown) return;
    if (widget.draft.text.isNotEmpty || _attached.isNotEmpty) return;
    _shortcut = shortcut;
    _setDraft(text);
    setState(() => _attached = attached);
  }

  /// Asks whether to clear the chat's history, which nothing here brings back.
  void _askReset() {
    _setDraft('');
    setState(() => _asking = true);
  }

  void _keepChat() => setState(() => _asking = false);

  void _clearChat() {
    setState(() => _asking = false);
    unawaited(_scope.chat.reset());
  }

  void _selectShortcut(PromptShortcut shortcut) {
    _scope.shell.closePopup(Popup.attach);
    _shortcut = shortcut;
    _setDraft('');
    setState(() => _shortcutsTab = false);
    widget.focus.requestFocus();
  }

  void _clearShortcut() => setState(() => _shortcut = null);

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final draft = widget.draft;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      // As tall as its card, however tall the window allows.
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.column),
          child: ListenableBuilder(
            listenable: _shown,
            builder: (context, _) {
              if (!scope.settings.configured) return const _NoKey();
              return _attachSheet(
                _Form(
                  draft: draft,
                  focus: widget.focus,
                  attached: _attached,
                  shortcut: _shortcut,
                  problem: _problem,
                  onAttach: () {
                    // The field gives up the keyboard, which would cover the sheet.
                    FocusManager.instance.primaryFocus?.unfocus();
                    scope.shell.togglePopup(Popup.attach);
                  },
                  onSelectShortcut: _selectShortcut,
                  onClearShortcut: _clearShortcut,
                  asking: _asking,
                  onAskReset: _askReset,
                  onKeepChat: _keepChat,
                  onClearChat: _clearChat,
                  onSend: _send,
                  onHold: _hold,
                  picking: _picking,
                  onPickModel: () => setState(() => _picking = !_picking),
                  onDictate: scope.dictation == null ? null : _dictate,
                  listening: _listening,
                  micProblem: _micProblem,
                  onInserted: (content) => switch (content.data) {
                    final bytes? => _pasted(bytes, content.mimeType),
                    null => false,
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  /// A message that is only a `/` and what is typed of a shortcut's name.
  static final _slashOnly = RegExp(r'^/\S*$');

  const _Form({
    required this.draft,
    required this.focus,
    required this.attached,
    required this.shortcut,
    required this.problem,
    required this.onAttach,
    required this.onSelectShortcut,
    required this.onClearShortcut,
    required this.asking,
    required this.onAskReset,
    required this.onKeepChat,
    required this.onClearChat,
    required this.onSend,
    required this.onHold,
    required this.picking,
    required this.onPickModel,
    required this.onDictate,
    required this.listening,
    required this.micProblem,
    required this.onInserted,
  });

  final TextEditingController draft;
  final FocusNode focus;
  final List<Attachment> attached;
  final PromptShortcut? shortcut;
  final String? problem;

  /// Opens the Attach sheet.
  final VoidCallback onAttach;
  final ValueChanged<PromptShortcut> onSelectShortcut;
  final VoidCallback onClearShortcut;

  /// Whether the person is being asked to clear the chat, and what each answer does.
  final bool asking;
  final VoidCallback onAskReset;
  final VoidCallback onKeepChat;
  final VoidCallback onClearChat;
  final ValueChanged<String> onSend;

  /// Puts the message after the ones waiting for the answer running here to end.
  final VoidCallback onHold;

  /// Whether the workspace's chat model picker shows, which [onPickModel] opens and closes.
  final bool picking;
  final VoidCallback onPickModel;

  /// Starts or ends dictation, or null where the device cannot listen.
  final VoidCallback? onDictate;
  final bool listening;

  /// Why dictation could not start, or null.
  final String? micProblem;

  /// Attaches content the keyboard inserts, such as a copied picture. Says whether it was a
  /// picture a message can carry.
  final bool Function(KeyboardInsertedContent content) onInserted;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final t = Tokens.of(context);
    final here = chat.answeringHere;
    final hint = here
        ? 'Answering…'
        : switch (scope.sources.chatMode.value) {
            ChatMode.automatic || ChatMode.chat => 'Ask anything…',
            ChatMode.query || null => 'Ask about your files…',
          };
    final slashQuery =
        shortcut == null &&
            draft.text.startsWith('/') &&
            scope.shell.popup.value == null &&
            !chat.busy &&
            _slashOnly.hasMatch(draft.text)
        ? draft.text.substring(1).toLowerCase()
        : null;
    final matches = slashQuery == null
        ? const <PromptShortcut>[]
        : scope.prefs
              .shortcutsIn(chat.activeSlug)
              .where(
                (item) =>
                    slashQuery.isEmpty ||
                    item.name.startsWith(slashQuery) ||
                    item.formerly.any((name) => name.startsWith(slashQuery)) ||
                    item.label.toLowerCase().startsWith(slashQuery),
              )
              .toList();
    // `/reset` is listed beside the shortcuts, on a chat that has a history to clear.
    final resetMatch =
        slashQuery != null && chat.canReset && 'reset'.startsWith(slashQuery);
    // A shortcut always has a prompt to send, so it needs a detail only when it asks for one.
    final filled = shortcut == null
        ? draft.text.trim().isNotEmpty
        : !(shortcut!.requiresDetail && draft.text.trim().isEmpty);
    final sendable = filled && chat.canSend(shortcut?.prompt ?? draft.text);

    void send() {
      if (sendable) onSend(draft.text);
    }

    void enter() {
      if (shortcut == null && slashQuery != null && matches.isNotEmpty) {
        onSelectShortcut(matches.first);
      } else if (resetMatch) {
        onAskReset();
      } else {
        send();
      }
    }

    // While this chat answers, each message typed waits its turn, to go when the answer before
    // it ends. Send becomes Send when done while the chat answers; while messages wait and
    // nothing answers, Send alone queues, unless they are held, when it sends at once. `/reset` is not one: it asks
    // first, which would hold up the messages after it.
    final holdable =
        filled &&
        chat.canSendWhenDone &&
        (shortcut != null || !isResetCommand(draft.text));

    // While a message typed now waits its turn, Enter and Send hold only what Send when done
    // would: never `/reset`. On a phone the keyboard's Enter is left to the field, which starts
    // a new line.
    final queues = chat.canSendWhenDone;
    final VoidCallback? hold = holdable ? onHold : null;
    final VoidCallback onEnter = queues ? () => hold?.call() : enter;
    final VoidCallback? tap = queues ? hold : (sendable ? send : null);
    final canTap = tap != null;
    final bindings = <ShortcutActivator, VoidCallback>{
      if (scope.enterSends) ...{
        const SingleActivator(LogicalKeyboardKey.enter): onEnter,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): onEnter,
      },
      if (shortcut != null && draft.text.isEmpty)
        const SingleActivator(LogicalKeyboardKey.backspace): onClearShortcut,
    };

    // What sits over the field, in the card's own padding.
    final notes = [
      if (problem case final problem?)
        AlertBox(AlertKind.bad, 'Could not attach', text: problem),
      if (micProblem case final problem?)
        AlertBox(AlertKind.bad, 'Could not listen', text: problem),
      if (asking)
        _FormNote(
          'Clear this chat? The model forgets it, and it no longer shows here or in AnythingLLM.',
          action: 'Clear',
          onAction: onClearChat,
          other: 'Keep',
          onOther: onKeepChat,
        ),
      if (picking) ...[
        ModelPicker(onClose: onPickModel),
        Divider(height: 21, thickness: 1, color: t.line),
      ],
    ];

    // One line of the field: its text's line and its padding, at least a button's 48.
    final line = math.max(
      48.0,
      MediaQuery.textScalerOf(context).scale(Type.chat) * Type.textAreaLine +
          24,
    );
    Widget oneLine(Widget button) => SizedBox(
      height: line,
      child: Center(child: button),
    );

    final card = AnswerFromAnchor(
      onPickModel: () {
        if (!picking) onPickModel();
      },
      child: Container(
        decoration: BoxDecoration(
          color: t.tile,
          borderRadius: BorderRadius.circular(Sizes.composer),
          border: Border.all(color: t.lineStrong),
          boxShadow: t.tileShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The notes scroll when the window leaves no room for them and the field, as on a
            // small phone with the keyboard up, from the end, where the shortcuts are.
            if (notes.isNotEmpty)
              Flexible(
                child: SingleChildScrollView(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: notes,
                  ),
                ),
              ),
            // The shortcuts a `/` finds, straight in the box over a rule, scrolling past about
            // five, and giving up room to the field where the window has little.
            if (slashQuery != null)
              Flexible(
                child: _ShortcutSuggestions(
                  query: slashQuery,
                  shortcuts: matches,
                  onSelect: onSelectShortcut,
                  onReset: resetMatch ? onAskReset : null,
                ),
              ),
            // What goes with the message: the shortcut, the files and where answers come from,
            // over the field. The row is no taller than nothing while none of them shows.
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  if (shortcut case final chosen?)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: ShortcutChip(
                        chosen.label,
                        maxWidth: 220,
                        onClear: onClearShortcut,
                      ),
                    ),
                  if (attached.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _FilesPill(attached.length, onTap: onAttach),
                    ),
                  // The model is a row in the Answer from sheet, since the row has room for
                  // one chip.
                  const AnswerFromChip(),
                ],
              ),
            ),
            // One line to start with, growing with the message up to 156. The buttons sit at the
            // foot, each centred on one line of the field, which is taller than 48 once the
            // text is large, so they stay level with the first line's words.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                oneLine(
                  IconBtn(
                    'plus',
                    tooltip: 'Add files or shortcuts to this message',
                    onPressed: chat.takesInput ? onAttach : null,
                    box: 48,
                    size: IconSize.small,
                  ),
                ),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 156),
                    child: CallbackShortcuts(
                      bindings: bindings,
                      child: FocusRing(
                        focus: focus,
                        child: FieldName(
                          label: shortcut == null
                              ? 'Message'
                              : 'Message, with the ${shortcut!.label} shortcut',
                          // Only the field follows the prefs, for its spellcheck.
                          child: ListenableBuilder(
                            listenable: scope.prefs,
                            builder: (context, _) => TextField(
                              controller: draft,
                              focusNode: focus,
                              enabled: chat.takesInput,
                              spellCheckConfiguration:
                                  scope.canSpellcheck &&
                                      scope.prefs.prefs.isOn(
                                        ChatSwitch.spellcheck,
                                      )
                                  ? const SpellCheckConfiguration()
                                  : const SpellCheckConfiguration.disabled(),
                              minLines: 1,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              textCapitalization: TextCapitalization.sentences,
                              style: Type.textArea(Type.chat, t.ink),
                              cursorColor: t.accent,
                              contentInsertionConfiguration:
                                  ContentInsertionConfiguration(
                                    allowedMimeTypes: imageMimes.toList(),
                                    onContentInserted: onInserted,
                                  ),
                              decoration: InputDecoration(
                                isCollapsed: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 12,
                                ),
                                border: InputBorder.none,
                                hintText: shortcut?.requiresDetail == true
                                    ? shortcut!.detailHint
                                    : shortcut == null
                                    ? hint
                                    : 'Add a detail (optional)',
                                hintStyle: Type.textArea(Type.chat, t.muted),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (onDictate != null)
                  oneLine(
                    IconBtn(
                      'mic',
                      tooltip: listening ? 'Stop dictating' : 'Dictate',
                      active: listening,
                      onPressed: chat.takesInput || listening
                          ? onDictate
                          : null,
                      box: 48,
                      size: IconSize.small,
                    ),
                  ),
                // The round button is 40 across in a 48 square, as the Lite prototype draws it.
                // While this chat answers it is Send when done once something is typed, and Stop
                // while nothing is.
                oneLine(
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: here && !holdable
                        ? RoundButton(
                            label: 'Stop the answer',
                            color: t.ink,
                            onTap: chat.stop,
                            child: const StopMark(),
                          )
                        : RoundButton(
                            label: here ? 'Send when done' : 'Send',
                            // Send is the accent with its glow while it can send, and sunken
                            // with a muted arrow while it cannot.
                            color: canTap ? t.accent : t.sunken,
                            glow: canTap,
                            onTap: canTap ? tap : null,
                            child: AppIcon(
                              'send',
                              size: IconSize.small,
                              color: canTap ? t.onAccent : t.muted,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return SizedBox(width: double.infinity, child: card);
  }
}

/// The shortcuts a `/` finds, in the message box's own tile over a rule above the field: rows
/// of 56, up to [maxHeight] before they scroll, with Clear this chat last where [onReset] is.
/// With none, a line says the message is sent as typed.
class _ShortcutSuggestions extends StatelessWidget {
  const _ShortcutSuggestions({
    required this.query,
    required this.shortcuts,
    required this.onSelect,
    required this.onReset,
  });

  final String query;
  final List<PromptShortcut> shortcuts;
  final ValueChanged<PromptShortcut> onSelect;

  /// What choosing `/reset` does, listed after the shortcuts; null when it is not listed.
  final VoidCallback? onReset;

  /// About five rows, and the room under the last.
  static const maxHeight = 290.0;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final rule = BoxDecoration(
      border: Border(bottom: BorderSide(color: t.line)),
    );
    if (shortcuts.isEmpty && onReset == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          decoration: rule,
          padding: const EdgeInsets.only(top: 16, bottom: 12),
          child: Text(
            'No shortcut called /$query. It is sent as typed.',
            style: Type.note(t.ink),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      child: DecoratedBox(
        decoration: rule,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: maxHeight),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 6),
            children: [
              for (final shortcut in shortcuts)
                _SlashRow(
                  shortcut.label,
                  name: shortcut.name,
                  heard: _heard(shortcut),
                  onTap: () => onSelect(shortcut),
                ),
              if (onReset case final reset?)
                _SlashRow(
                  'Clear this chat',
                  name: 'reset',
                  icon: 'trash',
                  heard: 'Clear this chat, /reset. Asks first',
                  onTap: reset,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a screen reader hears for [shortcut] in a list.
String _heard(PromptShortcut shortcut) =>
    '${shortcut.label}, /${shortcut.name}. Add to the message';

/// A row of the `/` list: [label] on one line, then its `/name` in mono, muted, at the end.
class _SlashRow extends StatelessWidget {
  const _SlashRow(
    this.label, {
    required this.name,
    required this.heard,
    required this.onTap,
    this.icon,
  });

  final String label;
  final String name;
  final String heard;
  final VoidCallback onTap;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: heard,
      onTap: onTap,
      radius: BorderRadius.circular(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            spacing: 14,
            children: [
              if (icon case final icon?)
                AppIcon(icon, size: IconSize.medium, color: t.ink),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.body(t.ink),
                ),
              ),
              Text('/$name', style: Type.mono(13, color: t.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A shortcut in a list: its label and its `/name`, which [onSelect] adds to the message.
class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow(this.shortcut, this.onSelect);

  final PromptShortcut shortcut;
  final ValueChanged<PromptShortcut> onSelect;

  @override
  Widget build(BuildContext context) => CardRow(
    shortcut.label,
    heard: _heard(shortcut),
    trailing: Text(
      '/${shortcut.name}',
      style: Type.mono(13, color: Tokens.of(context).ink),
    ),
    onTap: () => onSelect(shortcut),
  );
}

class _ShortcutPicker extends StatelessWidget {
  const _ShortcutPicker({required this.onSelect, required this.onManage});

  final ValueChanged<PromptShortcut> onSelect;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shortcuts = scope.prefs.shortcutsIn(scope.chat.activeSlug);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          const CardCaption(
            'Tap one to add it to your message, then add a detail if it asks. Type / in the message to find them too.',
          ),
          if (shortcuts.isNotEmpty)
            FieldCard([
              for (final shortcut in shortcuts)
                _ShortcutRow(shortcut, onSelect),
            ])
          else
            const HelpText('No shortcuts are available yet.'),
          FieldCard([
            CardRow(
              'Edit shortcuts',
              icon: 'pencil',
              onTap: onManage,
              trailing: AppIcon(
                'chevron',
                size: IconSize.xs,
                color: Tokens.of(context).muted,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// How many files go with the next message, which opens the Attach sheet.
class _FilesPill extends StatelessWidget {
  const _FilesPill(this.count, {required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final words = plural(count, 'file', 'files');
    return Tappable(
      touchTarget: true,
      label: '$words attached. Review',
      onTap: onTap,
      radius: BorderRadius.circular(99),
      color: t.accentSoft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          words,
          style: Type.caption(t.accent, weight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Stop's square, drawn in a [RoundButton] on [Tokens.ink].
class StopMark extends StatelessWidget {
  const StopMark({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: Tokens.of(context).ground,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// A round button [size] across, or a pill as wide as a [child] wider than that, such as Send.
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    required this.child,
    this.size = 40,
    this.glow = false,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;
  final Widget child;
  final double size;

  /// Whether it carries the glow of a screen's one primary action, as Send does when it can.
  final bool glow;

  @override
  Widget build(BuildContext context) => Tappable(
    touchTarget: true,
    label: label,
    tooltip: label,
    onTap: onTap,
    radius: BorderRadius.circular(99),
    color: color,
    shadows: glow ? Tokens.of(context).glow : const [],
    child: ConstrainedBox(
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      child: Center(widthFactor: 1, heightFactor: 1, child: child),
    ),
  );
}

/// A line over the field about the message, with the [action] that undoes it.
class _FormNote extends StatelessWidget {
  const _FormNote(
    this.text, {
    required this.action,
    required this.onAction,
    this.other,
    this.onOther,
  });

  final String text;
  final String action;
  final VoidCallback onAction;

  /// A second answer beside [action], such as Keep.
  final String? other;
  final VoidCallback? onOther;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(child: Text(text, style: Type.note(Tokens.of(context).ink))),
        if (other case final other?) ...[
          TextAction.plain(other, onOther!),
          const SizedBox(width: 12),
        ],
        if (other == null)
          TextAction('close', action, onAction)
        else
          TextAction.plain(action, onAction),
      ],
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
    final style = Type.note(t.warning);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: t.warningSoft,
        borderRadius: BorderRadius.circular(Sizes.notice),
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
                    text: 'Set up your AnythingLLM server in Settings to start asking.',
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
