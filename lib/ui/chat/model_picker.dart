import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/connection.dart';
import '../../core/providers.dart';
import '../../core/system_settings.dart';
import '../app_scope.dart';
import '../state/system_controller.dart';
import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import '../widgets/tappable.dart';

/// The provider the system answers with and its model, as GET /v1/system gives them, each
/// empty while not known.
({String provider, String model}) systemChatModel(
  Map<String, Object?>? values,
) {
  final provider = settingText(values, 'LLMProvider');
  return (
    provider: provider,
    model: settingText(values, chatModelKeys[provider] ?? ''),
  );
}

/// The model the open workspace answers with, its own or the system's, in the composer after
/// the server's name. Tapped, it opens the [ModelPicker].
class ModelChip extends StatefulWidget {
  const ModelChip({super.key, required this.open, required this.onTap});

  /// Whether the picker shows.
  final bool open;
  final VoidCallback onTap;

  @override
  State<ModelChip> createState() => _ModelChipState();
}

class _ModelChipState extends State<ModelChip> {
  /// The server the system's settings were asked of, so a failed read is not asked again on
  /// every rebuild.
  Connection? _asked;
  late final SystemController _system;

  @override
  void initState() {
    super.initState();
    _system = AppScope.of(context).system..addListener(_systemChanged);
  }

  @override
  void dispose() {
    _system.removeListener(_systemChanged);
    super.dispose();
  }

  /// Settings' pages tell the system's controller as they are built, which this chip, built
  /// elsewhere, follows after the frame.
  void _systemChanged() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.sources, scope.chat]),
      builder: (context, _) {
        final sources = scope.sources;
        final slug = scope.chat.activeSlug;
        if (sources.read == null || slug == null) {
          return const SizedBox.shrink();
        }
        final server = scope.chat.server;
        if (server != null && server != _asked) {
          _asked = server;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => unawaited(scope.system.wantSettings()),
          );
        }
        final system = systemChatModel(scope.system.settings);
        final model =
            sources.chatModel ??
            (sources.chatProvider == null && system.model.isNotEmpty
                ? system.model
                : null) ??
            (sources.chatProvider != null
                ? chatProviders.labelOf(sources.chatProvider!)
                : 'Chat model');
        final busy = scope.chat.answeringIn(slug);
        return Tappable(
          label: 'Chat model, $model',
          tooltip: 'The model this workspace answers with',
          expanded: widget.open,
          onTap: busy ? null : widget.onTap,
          dimWhenDisabled: 0.4,
          radius: BorderRadius.circular(6),
          color: widget.open ? t.hover : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(13, color: t.muted),
                  ),
                ),
                const SizedBox(width: 2),
                AppIcon('unfold', size: IconSize.xs, color: t.muted),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The open workspace's own provider and model, over the composer's field: System default, or
/// a provider and the model in its own name for it. Save writes them as the Files pane's
/// settings.json does; Use system default clears both.
class ModelPicker extends StatefulWidget {
  const ModelPicker({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<ModelPicker> {
  late String _provider;
  late final TextEditingController _model;
  String? _problem;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final sources = AppScope.of(context).sources;
    _provider = sources.chatProvider ?? '';
    _model = TextEditingController(text: sources.chatModel ?? '');
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _save(String? provider, String? model) async {
    setState(() {
      _saving = true;
      _problem = null;
    });
    final problem = await AppScope.of(context).sources
        .setChatModel(provider, model);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _problem = problem;
    });
    if (problem == null) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final system = systemChatModel(scope.system.settings);
    final systemLabel = system.provider.isEmpty
        ? 'System default'
        : 'System default (${chatProviders.labelOf(system.provider)})';
    final choices = [
      '',
      for (final p in chatProviders.providers) p.value,
      if (_provider.isNotEmpty && chatProviders.named(_provider) == null)
        _provider,
    ];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Semantics(
        container: true,
        label: 'Chat model',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Chat model for ${scope.chat.active?.name ?? 'this workspace'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(14, weight: FontWeight.w600, color: t.ink),
                  ),
                ),
                IconBtn(
                  'close',
                  tooltip: 'Close',
                  box: 28,
                  size: IconSize.xs,
                  onPressed: widget.onClose,
                ),
              ],
            ),
            const SizedBox(height: 8),
            AppSelect(
              value: _provider,
              choices: choices,
              labelOf: (v) =>
                  v.isEmpty ? systemLabel : chatProviders.labelOf(v),
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _provider = v ?? ''),
            ),
            const SizedBox(height: 8),
            AppField(
              controller: _model,
              label: 'Model',
              hint: "In the provider's own name for it.",
            ),
            const SizedBox(height: 6),
            HelpText(
              system.model.isEmpty
                  ? 'Empty uses the system default.'
                  : 'Empty uses the system default, ${system.model}.',
            ),
            if (_problem case final problem?) ...[
              const SizedBox(height: 8),
              AlertBox(
                AlertKind.bad,
                'Could not change the chat model',
                text: problem,
              ),
            ],
            const SizedBox(height: 10),
            ActionRow([
              AppButton(
                'Use system default',
                onPressed: _saving ? null : () => _save(null, null),
              ),
              AppButton(
                _saving ? 'Saving…' : 'Save',
                primary: true,
                onPressed: _saving
                    ? null
                    : () {
                        final model = _model.text.trim();
                        _save(
                          _provider.isEmpty ? null : _provider,
                          model.isEmpty ? null : model,
                        );
                      },
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
