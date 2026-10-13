import 'package:anywherellm/core/companion.dart';
import 'package:anywherellm/core/memory.dart';
import 'package:anywherellm/core/ports.dart';
import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/core/toolkit.dart';

import 'fake_companion.dart';

/// A [ToolkitApi] for widget tests that keeps the saved memories and the scheduled jobs in
/// memory. It is [present] unless a test makes it absent, as beside a stock AnythingLLM, and
/// serves every feature in [served].
class FakeToolkit with FakeCompanion implements ToolkitApi {
  FakeToolkit({this.present = true});

  @override
  bool present;

  @override
  Companion get companion => toolkitCompanion;

  @override
  Set<String> served = {ToolkitFeature.memories, ToolkitFeature.jobs};

  @override
  Future<List<ScheduledJob>> scheduledJobs() =>
      run('scheduledJobs', () => jobs);

  /// What [memorySwitches] answers, and [setMemorySwitches] changes.
  MemorySwitches switches = const MemorySwitches(enabled: true, learn: true);

  /// The saved memories for every workspace.
  final List<SavedMemory> globalMemories = [];

  /// Each workspace's own saved memories, by slug.
  final Map<String, List<SavedMemory>> workspaceMemories = {};

  /// An id no saved memory has, as the server numbers them.
  int get _nextMemory =>
      [
        0,
        for (final list in [globalMemories, ...workspaceMemories.values])
          for (final m in list) m.id,
      ].reduce((a, b) => a > b ? a : b) +
      1;

  @override
  Future<MemorySwitches> memorySwitches() =>
      run('memorySwitches', () => switches);

  @override
  Future<void> setMemorySwitches({bool? enabled, bool? learn}) => run(
    'setMemorySwitches',
    () => switches = MemorySwitches(
      enabled: enabled ?? switches.enabled,
      learn: learn ?? switches.learn,
    ),
    [
      ?enabled == null ? null : 'enabled=$enabled',
      ?learn == null ? null : 'learn=$learn',
    ].join(','),
  );

  /// Refuses a saved-memory call while they are off, as the server does.
  void _memoriesOn() {
    if (!switches.enabled) {
      throw const ApiException('Personalization is disabled.', status: 403);
    }
  }

  /// The list a saved memory for every workspace, or for [slug], goes in.
  List<SavedMemory> _memories(String? slug) => slug == null
      ? globalMemories
      : workspaceMemories.putIfAbsent(slug, () => []);

  /// Adds [memory] to the list for every workspace, or for [slug], unless it is full, as the
  /// server refuses it.
  SavedMemory _keepMemory(SavedMemory memory, String? slug) {
    final list = _memories(slug);
    final limit = slug == null ? globalMemoryLimit : workspaceMemoryLimit;
    if (list.length >= limit) {
      throw ApiException(
        'Maximum ${slug == null ? 'global' : 'workspace'} memory limit ($limit) reached.',
        status: 400,
      );
    }
    list.add(memory);
    return memory;
  }

  /// The list that holds saved memory [id], or a 404.
  List<SavedMemory> _holding(int id) =>
      [
        globalMemories,
        ...workspaceMemories.values,
      ].where((list) => list.any((m) => m.id == id)).firstOrNull ??
      (throw const ApiException('Memory not found.', status: 404));

  @override
  Future<SavedMemories> savedMemories(String slug) => run('savedMemories', () {
    _memoriesOn();
    return SavedMemories(
      global: [...globalMemories],
      workspace: [...?workspaceMemories[slug]],
    );
  }, slug);

  @override
  Future<SavedMemory> addMemory(
    String slug,
    String text, {
    required bool global,
  }) => run('addMemory', () {
    _memoriesOn();
    return _keepMemory(
      SavedMemory(id: _nextMemory, text: text, global: global),
      global ? null : slug,
    );
  }, text);

  @override
  Future<SavedMemory> editMemory(int id, String text) => run('editMemory', () {
    _memoriesOn();
    final list = _holding(id);
    final at = list.indexWhere((m) => m.id == id);
    return list[at] = SavedMemory(id: id, text: text, global: list[at].global);
  }, '$id');

  @override
  Future<void> deleteMemory(int id) => run('deleteMemory', () {
    _memoriesOn();
    _holding(id).removeWhere((m) => m.id == id);
  }, '$id');

  @override
  Future<SavedMemory> moveMemory(int id, {String? toWorkspace}) =>
      run('moveMemory', () {
        _memoriesOn();
        final list = _holding(id);
        final memory = list.firstWhere((m) => m.id == id);
        final moved = _keepMemory(
          SavedMemory(id: id, text: memory.text, global: toWorkspace == null),
          toWorkspace,
        );
        list.remove(memory);
        return moved;
      }, '$id:${toWorkspace ?? 'global'}');

  /// What [scheduledJobs] answers.
  List<ScheduledJob> jobs = const [];
}
