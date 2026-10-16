import 'dart:async';

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
import '../state/chat_controller.dart';
import '../state/turn.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/sheet.dart';
import '../widgets/tappable.dart';
import '../widgets/segmented.dart';
import 'answer_from.dart';
import 'attach_sheet.dart';
import 'dictation.dart';
import 'model_picker.dart';
import 'shortcut_chip.dart';

/// Whether [text] can be sent in the chat on screen: nothing runs, the chat is ready, a workspace
/// is open and there is something to send.
bool canSend(ChatController chat, String text) =>
    !chat.busy && chat.ready && chat.active != null && text.trim().isNotEmpty;

/// Where a question is written. On a desktop ([AppScope.enterSends]) Enter sends it and
/// Shift+Enter starts a new line; on a phone Enter starts a new line and Send sends. While this
/// chat answers, Send becomes Stop; while another chat answers, nothing can be sent. Files
/// attached go with the next question only.
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

  PromptShortcut? _shortcut;
  bool _shortcutsTab = false;

  /// Why the last pick added nothing, or null.
  String? _problem;

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
  /// with a message they were not picked for. Puts in what another app shared, with its files,
  /// unless something else was typed meanwhile.
  void _chatChanged() {
    final shown = _chatOnScreen();
    if (shown != _chatShown) {
      _chatShown = shown;
      if (_held != null ||
          _picking ||
          _shortcut != null ||
          _attached.isNotEmpty ||
          _problem != null) {
        setState(() {
          _held = null;
          _picking = false;
          _shortcut = null;
          _attached = const [];
          _problem = null;
        });
      }
    }
    _sendHeld();
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
            .where((item) => item.name == match[1]!.toLowerCase())
            .firstOrNull;
        if (shortcut != null) {
          _shortcut = shortcut;
          _setDraft(match[2] ?? '');
          return;
        }
      }
    }
    // Typing more lets go of a held message: what goes is what was held.
    _held = null;
    if (_listening && widget.draft.text != _dictated) {
      _go++;
      _scope.dictation?.stop();
      _listening = false;
    }
    setState(() => _typed = widget.draft.text);
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
    void close() => shell.closePopup(Popup.attach);
    return ValueListenableBuilder(
      valueListenable: shell.popup,
      builder: (context, popup, child) => PopupSheet(
        open: popup == Popup.attach,
        onClose: close,
        title: _shortcutsTab ? 'Shortcuts' : 'Attach',
        sheet: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Segmented<bool>(
              options: const [(false, 'Attach'), (true, 'Shortcuts')],
              value: _shortcutsTab,
              onChanged: (show) => setState(() => _shortcutsTab = show),
            ),
            if (_shortcutsTab)
              _ShortcutPicker(
                onSelect: _selectShortcut,
                onManage: () {
                  close();
                  shell.openSettings(SettingsPage.shortcuts);
                },
              )
            else
              AttachSheet(
                attached: _attached,
                onRemove: _remove,
                onPhotos: photos == null
                    ? null
                    : () => _pickWith(photos.choose, 'The photos did not open'),
                onCamera: photos == null
                    ? null
                    : () => _pickWith(
                        () async => [?await photos.take()],
                        'The camera did not open',
                      ),
                onFiles: _attach,
                onDone: close,
              ),
          ],
        ),
        child: child!,
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
    if (shortcut?.requiresDetail == true && text.trim().isEmpty) return;
    final message = shortcut?.expand(text) ?? text;
    if (message.trim().isEmpty) return;
    final attached = _attached;
    final shown = _chatShown;
    widget.draft.clear();
    _go++;
    if (_listening) _scope.dictation?.stop();
    setState(() {
      _attached = const [];
      _problem = null;
      _listening = false;
      _shortcut = null;
    });
    final sent = await _scope.chat.send(
      message,
      attachments: attached,
      shortcutUse: shortcut == null
          ? null
          : ShortcutUse(label: shortcut.label, detail: text.trim()),
    );
    if (sent || !mounted || _chatShown != shown) return;
    if (widget.draft.text.isNotEmpty || _attached.isNotEmpty) return;
    _shortcut = shortcut;
    _setDraft(text);
    setState(() => _attached = attached);
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
      child: Center(
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
                  onSend: _send,
                  held: _held != null,
                  onHold: _hold,
                  onRelease: _release,
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
    required this.onSend,
    required this.held,
    required this.onHold,
    required this.onRelease,
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
        : chat.workspaceAnswering
        ? 'Another chat in this workspace is still answering…'
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
                    item.label.toLowerCase().startsWith(slashQuery),
              )
              .toList();
    // A shortcut always has a prompt to send, so it needs a detail only when it asks for one.
    final sendable = shortcut == null
        ? canSend(chat, draft.text)
        : canSend(chat, shortcut!.prompt) &&
              !(shortcut!.requiresDetail && draft.text.trim().isEmpty);

    void send() {
      if (sendable) onSend(draft.text);
    }

    void enter() {
      if (shortcut == null && slashQuery != null && matches.isNotEmpty) {
        onSelectShortcut(matches.first);
      } else {
        send();
      }
    }

    // While this chat answers, a message typed is held to go when the answer ends. Send when
    // done takes the chips' place, as they are off while the chat answers.
    final holdable = here && !held && draft.text.trim().isNotEmpty;

    // On a phone the keyboard's Enter is left to the field, which starts a new line.
    final VoidCallback onEnter = here ? onHold : enter;
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
      if (slashQuery != null)
        _ShortcutSuggestions(
          query: slashQuery,
          shortcuts: matches,
          onSelect: onSelectShortcut,
        ),
    ];

    final card = AnswerFromAnchor(
      onPickModel: () {
        if (!picking) onPickModel();
      },
      child: Container(
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(Sizes.composer),
          border: Border.all(color: t.line2),
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
            if (notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: notes,
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
                  if (holdable)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _SendWhenDone(onTap: onHold),
                    ),
                ],
              ),
            ),
            // One line to start with, growing with the message up to 156.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconBtn(
                  'plus',
                  tooltip: 'Add files or shortcuts to this message',
                  onPressed: chat.busy ? null : onAttach,
                  box: 48,
                  size: IconSize.small,
                ),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 156),
                    child: CallbackShortcuts(
                      bindings: bindings,
                      child: Semantics(
                        label: shortcut == null
                            ? 'Message'
                            : 'Message, with the ${shortcut!.label} shortcut',
                        textField: true,
                        // Only the field follows the prefs, for its spellcheck.
                        child: ListenableBuilder(
                          listenable: scope.prefs,
                          builder: (context, _) => TextField(
                            controller: draft,
                            focusNode: focus,
                            enabled: !chat.busy || here,
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
                if (onDictate != null)
                  IconBtn(
                    'mic',
                    tooltip: listening ? 'Stop dictating' : 'Dictate',
                    active: listening,
                    onPressed: chat.busy ? null : onDictate,
                    box: 48,
                    size: IconSize.small,
                  ),
                // The round button is 40 across in a 48 square, as the Lite prototype draws it.
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: here
                      ? RoundButton(
                          label: 'Stop the answer',
                          color: t.ink,
                          onTap: chat.stop,
                          child: const StopMark(),
                        )
                      : RoundButton(
                          label: 'Send',
                          // Send keeps the accent, as the Lite prototype draws it.
                          color: t.accent,
                          onTap: sendable ? send : null,
                          child: AppIcon(
                            'send',
                            size: IconSize.small,
                            color: t.onaccent,
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

class _ShortcutSuggestions extends StatelessWidget {
  const _ShortcutSuggestions({
    required this.query,
    required this.shortcuts,
    required this.onSelect,
  });

  final String query;
  final List<PromptShortcut> shortcuts;
  final ValueChanged<PromptShortcut> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: cardDecoration(t)
          .copyWith(boxShadow: [BoxShadow(color: t.shadow, blurRadius: 18)]),
      child: shortcuts.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No shortcut called /$query. It is sent as typed.',
                style: Type.sans(14, color: t.muted),
              ),
            )
          : ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(6),
              children: [
                for (final shortcut in shortcuts)
                  _ShortcutRow(shortcut, onSelect, large: true),
              ],
            ),
    );
  }
}

/// A shortcut in a list: its label and its `/name`, which [onSelect] adds to the message.
class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow(this.shortcut, this.onSelect, {this.large = false});

  final PromptShortcut shortcut;
  final ValueChanged<PromptShortcut> onSelect;
  final bool large;

  @override
  Widget build(BuildContext context) => CardRow(
    shortcut.label,
    icon: 'slash',
    large: large,
    heard: '${shortcut.label}, /${shortcut.name}. Add to the message',
    trailing: Text(
      '/${shortcut.name}',
      style: Type.mono(12, color: Tokens.of(context).muted),
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
          CardRow('Edit shortcuts', icon: 'pencil', onTap: onManage),
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
      color: t.accentbg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          words,
          style: Type.sans(13, weight: FontWeight.w600, color: t.accent),
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
      color: Tokens.of(context).bg,
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
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) => Tappable(
    touchTarget: true,
    label: label,
    tooltip: label,
    onTap: onTap,
    radius: BorderRadius.circular(99),
    color: color,
    child: ConstrainedBox(
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      child: Center(widthFactor: 1, heightFactor: 1, child: child),
    ),
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
/// Send now: a chat runs one answer at a time.
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
      radius: BorderRadius.circular(Sizes.small),
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
