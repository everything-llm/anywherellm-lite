import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../app_scope.dart';
import '../layout.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../settings/rows.dart';
import '../widgets/basics.dart';
import '../widgets/menu.dart';
import '../widgets/phone_page.dart';
import '../widgets/radio_card.dart';
import '../widgets/sheet.dart';
import '../widgets/tappable.dart';
import 'composer_chip.dart';
import 'model_picker.dart';

/// The Answer from chip and its menu tap as one: a tap on the chip is not a tap outside.
final Object _group = Object();

/// Whether the open workspace's chat mode can be changed now: it has been read, and no answer
/// runs in it.
bool _canChoose(AppScope scope) {
  final slug = scope.chat.activeSlug;
  return slug != null &&
      scope.sources.read != null &&
      !scope.chat.answeringIn(slug);
}

/// The open workspace's chat mode in the composer, in plain words: what answers draw on. Tapped,
/// it opens the Answer from menu over the composer ([AnswerFromAnchor]). Files only tints it,
/// since that mode is the one that makes an answer decline. It shows once the workspace is read
/// and only while its mode is not the default, Files, knowledge & tools, and reads Answer from
/// when the server's mode is none the app knows. It is off while an answer runs in the
/// workspace.
class AnswerFromChip extends StatefulWidget {
  const AnswerFromChip({super.key});

  @override
  State<AnswerFromChip> createState() => _AnswerFromChipState();
}

class _AnswerFromChipState extends State<AnswerFromChip> {
  late final AppScope _scope;

  /// Whether the open workspace has been read, the one thing the chip takes from Sources
  /// beside its mode.
  late bool _read;

  @override
  void initState() {
    super.initState();
    _scope = AppScope.of(context);
    _read = _scope.sources.read != null;
    _scope.sources.addListener(_sourcesChanged);
  }

  @override
  void dispose() {
    _scope.sources.removeListener(_sourcesChanged);
    super.dispose();
  }

  void _sourcesChanged() {
    final read = _scope.sources.read != null;
    if (read != _read) setState(() => _read = read);
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    return ListenableBuilder(
      listenable: Listenable.merge([
        scope.shell.popup,
        scope.chat,
        scope.sources.chatMode,
      ]),
      builder: (context, _) {
        if (scope.chat.activeSlug == null || !_read) {
          return const SizedBox.shrink();
        }
        final mode = scope.sources.chatMode.value;
        // The default needs no saying: the chip shows only for another mode, and the choice
        // otherwise lives in the workspace's Answer settings.
        if (mode == ChatMode.automatic && !scope.shell.answerFromOpen) {
          return const SizedBox.shrink();
        }
        final text = mode?.title ?? 'Answer from';
        return TapRegion(
          groupId: _group,
          child: ComposerChip(
            text: text,
            label: mode == null ? text : 'Answer from: $text',
            tooltip: 'What answers in this workspace draw on',
            open: scope.shell.answerFromOpen,
            tinted: mode == ChatMode.query,
            onTap: _canChoose(scope)
                ? () => scope.shell.togglePopup(Popup.answerFrom)
                : null,
          ),
        );
      },
    );
  }
}

/// [child], the composer's card, with the Answer from menu above it while
/// [ShellController.answerFromOpen], 348 px wide from the chip's edge, or on a phone a sheet
/// that ends with the Chat model row [onPickModel] answers. A tap outside, Esc or Back closes
/// it, and so do another workspace and an answer starting in this one.
class AnswerFromAnchor extends StatefulWidget {
  const AnswerFromAnchor({
    super.key,
    required this.onPickModel,
    required this.child,
  });

  final VoidCallback onPickModel;
  final Widget child;

  @override
  State<AnswerFromAnchor> createState() => _AnswerFromAnchorState();
}

class _AnswerFromAnchorState extends State<AnswerFromAnchor> {
  late final AppScope _scope;
  String? _slug;

  @override
  void initState() {
    super.initState();
    _scope = AppScope.of(context);
    _slug = _scope.chat.activeSlug;
    _scope.chat.addListener(_chatChanged);
  }

  @override
  void dispose() {
    _scope.chat.removeListener(_chatChanged);
    super.dispose();
  }

  void _close() => _scope.shell.closePopup(Popup.answerFrom);

  void _chatChanged() {
    final slug = _scope.chat.activeSlug;
    final moved = slug != _slug;
    _slug = slug;
    if (moved || (slug != null && _scope.chat.answeringIn(slug))) _close();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    final listened = Listenable.merge([
      scope.chat,
      scope.sources,
      scope.sources.chatMode,
      scope.system,
    ]);
    // A phone's choice is a sheet over the window, its modes as cards.
    if (ScreenClass.ofContext(context).isPhone) {
      return ValueListenableBuilder(
        valueListenable: scope.shell.popup,
        builder: (context, popup, child) => PopupSheet(
          open: popup == Popup.answerFrom,
          onClose: _close,
          title: 'Answer from',
          sheet: (context) => ListenableBuilder(
            listenable: listened,
            builder: (context, _) {
              if (!_canChoose(scope)) return const SizedBox.shrink();
              scope.system.wantSettingsOnce();
              return _Sheet(onPickModel: widget.onPickModel, onClose: _close);
            },
          ),
          child: child!,
        ),
        child: widget.child,
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final card = box.maxWidth;
        final width = math.min(348.0, card);
        return ValueListenableBuilder(
          valueListenable: scope.shell.popup,
          builder: (context, popup, child) => PopupAnchor(
            open: popup == Popup.answerFrom,
            onClose: _close,
            group: _group,
            above: true,
            width: width,
            offset: Offset(math.min(76.0, card - width), -8),
            menu: (context) => ListenableBuilder(
              listenable: listened,
              builder: (context, _) => _canChoose(scope)
                  ? _Menu(onClose: _close)
                  : const SizedBox.shrink(),
            ),
            child: child!,
          ),
          child: widget.child,
        );
      },
    );
  }
}

/// A phone's Answer from sheet: the three modes as cards, a note that the choice is the
/// workspace's, and the Model row, since the composer has room for one chip.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.onPickModel, required this.onClose});

  final VoidCallback onPickModel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final mode = scope.sources.chatMode.value;
    final workspace = scope.chat.active?.name ?? 'this workspace';
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          for (final m in ChatMode.values)
            Semantics(
              inMutuallyExclusiveGroup: true,
              checked: m == mode,
              child: RadioCard(
                title: m.title,
                about: m.detail,
                selected: m == mode,
                onTap: () {
                  onClose();
                  unawaited(scope.sources.setChatMode(m));
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(
              'Applies to every chat in $workspace.',
              style: Type.sans(13, color: t.muted, height: 1.4),
            ),
          ),
          FieldCard(inSheet: true, [
            NavRow(
              title: 'Chat model',
              about: workspaceModel(scope),
              onTap: () {
                onClose();
                onPickModel();
              },
            ),
          ]),
        ],
      ),
    );
  }
}

/// The Answer from menu: the three modes, and a note that the choice is the workspace's.
class _Menu extends StatelessWidget {
  const _Menu({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final mode = scope.sources.chatMode.value;
    final workspace = scope.chat.active?.name ?? 'this workspace';
    final note = Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
      child: Text(
        'Applies to every chat in $workspace.',
        style: Type.sans(12, color: t.muted, height: 1.4),
      ),
    );
    return AppMenu(
      label: 'Answer from',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          child: const SectionLabel('Answer from'),
        ),
        for (final m in ChatMode.values)
          _Choice(
            m,
            chosen: m == mode,
            onTap: () {
              onClose();
              unawaited(scope.sources.setChatMode(m));
            },
          ),
        const MenuDivider(),
        note,
      ],
    );
  }
}

/// One mode: a radio, what it answers from and the line under that.
class _Choice extends StatelessWidget {
  const _Choice(this.mode, {required this.chosen, required this.onTap});

  final ChatMode mode;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final radio = Container(
      width: 16,
      height: 16,
      margin: const EdgeInsets.only(top: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: chosen ? t.accent : t.fade, width: 1.5),
      ),
      child: chosen
          ? Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: t.accent,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: chosen,
      child: Tappable(
        label: mode.title,
        selected: chosen,
        onTap: onTap,
        radius: BorderRadius.circular(10),
        color: chosen ? t.sel : null,
        excludeSemantics: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              radio,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 1,
                  children: [
                    Text(
                      mode.title,
                      style: Type.sans(
                        13.5,
                        weight: chosen ? FontWeight.w600 : FontWeight.w500,
                        color: t.ink,
                      ),
                    ),
                    Text(
                      mode.detail,
                      style: Type.sans(12.5, color: t.muted, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
