import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/connection.dart';
import '../../core/providers.dart';
import '../../core/system_settings.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/fields.dart';
import 'composer_chip.dart';

/// The model the open workspace answers with: its own, its own provider's name when it names no
/// model, the system's, or `Chat model` while none is known.
String workspaceModel(AppScope scope) {
  final sources = scope.sources;
  final system = systemChatModel(scope.system.settings);
  return switch ((sources.chatModel, sources.chatProvider)) {
    (final own?, _) => own,
    (_, final provider?) => chatProviders.labelOf(provider),
    _ when system.model.isNotEmpty => system.model,
    _ => 'Chat model',
  };
}

/// The model the open workspace answers with, its own or the system's, in the composer after
/// the Answer from chip on a desktop. Tapped, it opens the [ModelPicker]. It asks for the
/// system's settings once a server, for the system's model.
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

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.sources, scope.chat, scope.system]),
      builder: (context, _) {
        final slug = scope.chat.activeSlug;
        if (scope.sources.read == null || slug == null) {
          return const SizedBox.shrink();
        }
        final server = scope.chat.server;
        if (server != null && server != _asked) {
          _asked = server;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => unawaited(scope.system.wantSettings()),
          );
        }
        final model = workspaceModel(scope);
        return ComposerChip(
          text: model,
          label: 'Chat model, $model',
          tooltip: 'The model this workspace answers with',
          open: widget.open,
          onTap: scope.chat.answeringIn(slug) ? null : widget.onTap,
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
    // The providers the server takes, as Settings' Chat model page offers them.
    final choices = [
      '',
      ...chatProviders.choices(_provider).where((v) => v.isNotEmpty),
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
