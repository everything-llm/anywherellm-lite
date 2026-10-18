/// A local prompt shortcut, available in every workspace or one workspace only.
class PromptShortcut {
  const PromptShortcut({
    required this.id,
    required this.name,
    required this.label,
    required this.prompt,
    this.workspaceKey,
    this.requiresDetail = false,
    this.detailHint = 'Add a detail',
    this.barePrompt,
  });

  final String id;
  final String name;
  final String label;
  final String prompt;
  final String? workspaceKey;
  final bool requiresDetail;
  final String detailHint;
  final String? barePrompt;

  bool appliesTo(String? workspaceKey) =>
      this.workspaceKey == null || this.workspaceKey == workspaceKey;

  /// This shortcut kept for the workspace [workspaceKey] instead.
  PromptShortcut inWorkspace(String workspaceKey) => PromptShortcut(
    id: id,
    name: name,
    label: label,
    prompt: prompt,
    workspaceKey: workspaceKey,
    requiresDetail: requiresDetail,
    detailHint: detailHint,
    barePrompt: barePrompt,
  );

  static final _placeholder = RegExp(r'\s*\{text\}\s*[.,!?;:]?');
  static final _spaces = RegExp(r'\s+');
  static final _spaceBeforeMark = RegExp(r'\s+([.,!?;:])');

  /// The question sent for this shortcut and [detail], following its `{text}` placeholder.
  String expand(String detail) {
    final value = detail.trim();
    if (!prompt.contains('{text}')) {
      return [prompt.trim(), if (value.isNotEmpty) value].join(' ');
    }
    if (value.isEmpty && barePrompt != null) return barePrompt!.trim();
    if (value.isEmpty) {
      return prompt
          .replaceAllMapped(_placeholder, (_) => ' ')
          .replaceAll(_spaces, ' ')
          .trim();
    }
    return prompt
        .replaceAll('{text}', value)
        .replaceAll(_spaceBeforeMark, r'$1')
        .trim();
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'label': label,
    'prompt': prompt,
    if (workspaceKey != null) 'workspaceKey': workspaceKey,
    if (requiresDetail) 'requiresDetail': true,
    if (detailHint != 'Add a detail') 'detailHint': detailHint,
    if (barePrompt != null) 'barePrompt': barePrompt,
  };

  static PromptShortcut? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final label = json['label'];
    final prompt = json['prompt'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        !_shortcutName.hasMatch(name) ||
        label is! String ||
        label.trim().isEmpty ||
        prompt is! String ||
        prompt.trim().isEmpty) {
      return null;
    }
    return PromptShortcut(
      id: id,
      name: name,
      label: label.trim(),
      prompt: prompt.trim(),
      workspaceKey: json['workspaceKey'] is String
          ? json['workspaceKey'] as String
          : null,
      requiresDetail: json['requiresDetail'] == true,
      detailHint: json['detailHint'] is String
          ? (json['detailHint'] as String).trim()
          : 'Add a detail',
      barePrompt: json['barePrompt'] is String
          ? (json['barePrompt'] as String).trim()
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PromptShortcut &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          label == other.label &&
          prompt == other.prompt &&
          workspaceKey == other.workspaceKey &&
          requiresDetail == other.requiresDetail &&
          detailHint == other.detailHint &&
          barePrompt == other.barePrompt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    label,
    prompt,
    workspaceKey,
    requiresDetail,
    detailHint,
    barePrompt,
  );
}

/// What a shortcut sent, retained locally for the optional compact transcript display.
class ShortcutUse {
  const ShortcutUse({required this.label, required this.detail});

  final String label;
  final String detail;

  Map<String, Object?> toJson() => {'label': label, 'detail': detail};

  static ShortcutUse? fromJson(Object? json) {
    if (json is! Map || json['label'] is! String || json['detail'] is! String) {
      return null;
    }
    return ShortcutUse(
      label: json['label'] as String,
      detail: json['detail'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShortcutUse &&
          runtimeType == other.runtimeType &&
          label == other.label &&
          detail == other.detail;

  @override
  int get hashCode => Object.hash(label, detail);
}

/// Whether [text] is the `/reset` command, which clears the chat's history instead of being
/// sent.
bool isResetCommand(String text) => text.trim().toLowerCase() == '/reset';

/// A shortcut identifier accepted by the composer and editor.
final _shortcutName = RegExp(r'^[a-z][a-z0-9-]{0,23}$');

bool validShortcutName(String name) => _shortcutName.hasMatch(name);

/// The prompts built into the app, which cannot be edited or deleted.
const builtInPromptShortcuts = [
  PromptShortcut(
    id: 'summarize',
    name: 'summarize',
    label: 'Summarise',
    prompt: 'Summarise {text}.',
    barePrompt: 'Summarise this chat so far in a few lines.',
  ),
  PromptShortcut(
    id: 'shorter',
    name: 'shorter',
    label: 'Make it shorter',
    prompt: 'Say your last answer again in half the words.',
  ),
  PromptShortcut(
    id: 'explain',
    name: 'explain',
    label: 'Explain simply',
    prompt: 'Explain {text} in plain words, as if to someone new to it.',
    barePrompt:
        'Explain your last answer in plain words, as if to someone new to it.',
  ),
  PromptShortcut(
    id: 'list',
    name: 'list',
    label: 'Make a list',
    prompt: 'Turn your last answer into a short checklist.',
  ),
  PromptShortcut(
    id: 'translate',
    name: 'translate',
    label: 'Translate',
    prompt: 'Translate your last answer into {text}.',
    requiresDetail: true,
    detailHint: 'Which language?',
  ),
];

/// The built-in shortcuts offered under the chat's last answer, in this order, each sent with
/// no detail.
final followUpShortcuts = [
  for (final id in const ['shorter', 'explain', 'list'])
    builtInPromptShortcuts.firstWhere((shortcut) => shortcut.id == id),
];
