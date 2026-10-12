/// How many saved memories AnythingLLM keeps for every workspace.
const globalMemoryLimit = 5;

/// How many saved memories AnythingLLM keeps for each workspace.
const workspaceMemoryLimit = 20;

/// The longest saved memory the server takes, in characters.
const memoryTextMax = 500;

/// One of AnythingLLM's saved memories: a short fact every chat of its workspace, or of every
/// workspace when [global], is shown word for word.
class SavedMemory {
  const SavedMemory({
    required this.id,
    required this.text,
    required this.global,
  });

  final int id;
  final String text;
  final bool global;

  /// The memory as the server gives it (`id`, `content`, `scope`), or null for anything else.
  static SavedMemory? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final text = json['content'];
    if (id is! num || text is! String) return null;
    return SavedMemory(
      id: id.toInt(),
      text: text,
      global: json['scope'] == 'global',
    );
  }
}

/// The saved memories a workspace's chats are shown: those for every workspace and its own.
class SavedMemories {
  const SavedMemories({this.global = const [], this.workspace = const []});

  final List<SavedMemory> global;
  final List<SavedMemory> workspace;

  /// The memories as `GET /api/workspaces/{slug}/memories` answers them, under `memories`.
  static SavedMemories fromJson(Object? json) {
    final memories = json is Map ? json['memories'] : null;
    List<SavedMemory> listed(Object? list) => [
      if (list is List)
        for (final item in list) ?SavedMemory.fromJson(item),
    ];
    if (memories is! Map) return const SavedMemories();
    return SavedMemories(
      global: listed(memories['global']),
      workspace: listed(memories['workspace']),
    );
  }
}

/// Whether AnythingLLM keeps saved memories at all, and whether it also saves them itself from
/// what it notices in chats.
class MemorySwitches {
  const MemorySwitches({required this.enabled, required this.learn});

  final bool enabled;
  final bool learn;

  /// The switches as the server's preferences give them, under `settings`: `memory_enabled` is
  /// off unless `true`, and `memory_auto_extraction` on unless `false`, as AnythingLLM reads them.
  static MemorySwitches fromJson(Object? json) {
    final settings = json is Map ? json['settings'] : null;
    final values = settings is Map ? settings : const {};
    return MemorySwitches(
      enabled: '${values['memory_enabled']}' == 'true',
      learn: '${values['memory_auto_extraction']}' != 'false',
    );
  }
}
