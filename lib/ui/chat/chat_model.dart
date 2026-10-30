import 'package:flutter/material.dart';

import '../../core/providers.dart';
import '../../core/system_settings.dart';
import '../app_scope.dart';
import '../settings/rows.dart';
import '../widgets/fields.dart';

/// What the open workspace answers with, as its Chat model rows name it: its own model, its own
/// provider's name when it names no model, or else `System default (glm-5.3)`, with the system's
/// model, or its provider's name where that names none, once the server's settings are read.
String workspaceModel(AppScope scope) {
  final sources = scope.sources;
  if (sources.chatModel case final own?) return own;
  if (sources.chatProvider case final provider?) {
    return chatProviders.labelOf(provider);
  }
  final system = systemChatModel(scope.system.settings);
  final name = system.model.isNotEmpty
      ? system.model
      : system.provider.isEmpty
      ? null
      : chatProviders.labelOf(system.provider);
  return name == null ? 'System default' : 'System default ($name)';
}

/// The model the open workspace answers with, for the line an answer waits on: its own, its own
/// provider's name when it names no model, the system's, or null while none is known.
String? knownWorkspaceModel(AppScope scope) {
  final sources = scope.sources;
  final system = systemChatModel(scope.system.settings);
  return switch ((sources.chatModel, sources.chatProvider)) {
    (final own?, _) => own,
    (_, final provider?) => chatProviders.labelOf(provider),
    _ when system.model.isNotEmpty => system.model,
    _ => null,
  };
}

/// The line under a card that names a chat model. The app shows the model and never changes it:
/// the developer API cannot list a provider's models, so AnythingLLM's own web page changes it.
class ChatModelNote extends StatelessWidget {
  const ChatModelNote({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(FieldCard.inset, 8, FieldCard.inset, 0),
    child: HelpText("The chat model is changed in AnythingLLM's web page."),
  );
}
