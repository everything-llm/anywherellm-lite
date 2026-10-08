import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/chat.dart';
import '../../core/connection.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
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
/// since that mode is the one that makes an answer decline. It shows once the workspace is read,
/// and reads Answer from when the server's mode is none the app knows. It is off while an answer
/// runs in the workspace.
class AnswerFromChip extends StatelessWidget {
  const AnswerFromChip({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        scope.shell,
        scope.chat,
        scope.sources,
        scope.sources.chatMode,
      ]),
      builder: (context, _) {
        if (scope.chat.activeSlug == null || scope.sources.read == null) {
          return const SizedBox.shrink();
        }
        final mode = scope.sources.chatMode.value;
        final text = mode?.title ?? 'Answer from';
        return TapRegion(
          groupId: _group,
          child: ComposerChip(
            text: text,
            label: mode == null ? text : 'Answer from: $text',
            tooltip: 'What answers in this workspace draw on',
            open: scope.shell.answerFromOpen,
            tinted: mode == ChatMode.query,
            onTap: _canChoose(scope) ? scope.shell.toggleAnswerFrom : null,
          ),
        );
      },
    );
  }
}

/// [child], the composer's card, with the Answer from menu above it while
/// [ShellController.answerFromOpen]: 348 px wide from the chip's edge on a desktop, the card's
/// width on a phone, where it ends with the Model row that [onPickModel] answers. A tap outside,
/// Esc or Back closes it, and so do another workspace and an answer starting in this one.
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
  // Always showing: the overlay draws nothing while the menu is closed.
  final _portal = OverlayPortalController()..show();
  final _link = LayerLink();
  late final AppScope _scope;
  String? _slug;

  /// The server the system's settings were asked of for the Model row, so a failed read is not
  /// asked again on every rebuild.
  Connection? _asked;

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

  void _chatChanged() {
    final slug = _scope.chat.activeSlug;
    final moved = slug != _slug;
    _slug = slug;
    if (moved || (slug != null && _scope.chat.answeringIn(slug))) {
      _scope.shell.closeAnswerFrom();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => _overlay(context, box.maxWidth),
        child: widget.child,
      ),
    ),
  );

  Widget _overlay(BuildContext context, double cardWidth) {
    final scope = _scope;
    return ListenableBuilder(
      listenable: Listenable.merge([
        scope.shell,
        scope.chat,
        scope.sources,
        scope.sources.chatMode,
        scope.system,
      ]),
      builder: (context, _) {
        if (!scope.shell.answerFromOpen || !_canChoose(scope)) {
          return const SizedBox.shrink();
        }
        final phone = ScreenClass.ofContext(context).isPhone;
        final server = scope.chat.server;
        if (phone && server != null && server != _asked) {
          _asked = server;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => unawaited(scope.system.wantSettings()),
          );
        }
        final width = phone ? cardWidth : math.min(348.0, cardWidth);
        final left = phone ? 0.0 : math.min(76.0, cardWidth - width);
        return CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          offset: Offset(left, -8),
          showWhenUnlinked: false,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: TapRegion(
              groupId: _group,
              onTapOutside: (_) => scope.shell.closeAnswerFrom(),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape):
                      scope.shell.closeAnswerFrom,
                },
                child: Focus(
                  autofocus: true,
                  child: SizedBox(
                    width: width,
                    child: _Menu(phone: phone, onPickModel: widget.onPickModel),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The Answer from menu: the three modes, and a note that the choice is the workspace's. On a
/// phone the Model row comes before the note, since the composer has room for one chip.
class _Menu extends StatelessWidget {
  const _Menu({required this.phone, required this.onPickModel});

  final bool phone;
  final VoidCallback onPickModel;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final mode = scope.sources.chatMode.value;
    final workspace = scope.chat.active?.name ?? 'this workspace';
    final note = Text(
      '${phone ? 'Both apply' : 'Applies'} to every chat in $workspace.',
      style: Type.sans(12, color: t.muted, height: 1.4),
    );
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(phone ? 14 : 12),
        border: Border.all(color: t.line),
        boxShadow: [
          BoxShadow(
            color: t.shadow,
            // Flutter blurs a radius more than CSS does; 34 here is CSS's 40.
            blurRadius: 34,
            spreadRadius: -12,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Semantics(
        container: true,
        label: 'Answer from',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 2,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(10, phone ? 8 : 6, 10, 4),
              child: const SectionLabel('Answer from'),
            ),
            for (final m in ChatMode.values)
              _Choice(
                m,
                chosen: m == mode,
                phone: phone,
                onTap: () {
                  scope.shell.closeAnswerFrom();
                  unawaited(scope.sources.setChatMode(m));
                },
              ),
            if (phone) ...[
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: t.line2,
              ),
              _ModelRow(
                onTap: () {
                  scope.shell.closeAnswerFrom();
                  onPickModel();
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: note,
              ),
            ] else
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.line2)),
                ),
                child: note,
              ),
          ],
        ),
      ),
    );
  }
}

/// One mode: a radio, what it answers from and the line under that.
class _Choice extends StatelessWidget {
  const _Choice(
    this.mode, {
    required this.chosen,
    required this.phone,
    required this.onTap,
  });

  final ChatMode mode;
  final bool chosen;
  final bool phone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final radio = Container(
      width: 16,
      height: 16,
      margin: EdgeInsets.only(top: phone ? 0 : 2),
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
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: phone ? 52 : 0),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: phone ? 6 : 8,
            ),
            child: Row(
              crossAxisAlignment: phone
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              spacing: phone ? 12 : 10,
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
                          phone ? 14.5 : 13.5,
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
      ),
    );
  }
}

/// The phone's Model row: the model the workspace answers with, which opens the model picker.
class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final model = workspaceModel(scope);
    return Tappable(
      label: 'Chat model, $model',
      onTap: onTap,
      radius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            spacing: 10,
            children: [
              Text(
                'Model',
                style: Type.sans(14.5, weight: FontWeight.w500, color: t.ink),
              ),
              Expanded(
                child: Text(
                  model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Type.sans(13.5, color: t.muted),
                ),
              ),
              AppIcon('chevron', size: IconSize.xs, color: t.muted),
            ],
          ),
        ),
      ),
    );
  }
}
