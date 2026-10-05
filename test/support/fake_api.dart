import 'package:everything/core/models.dart';
import 'package:everything/core/ports.dart';

/// A [NilsApi] for widget tests. Set the fields to change what it answers, and put an error in
/// [errors] under a method's name to make it fail. Every call is recorded in [calls] as `name`
/// or `name:arg`.
class FakeApi implements NilsApi {
  Overview overviewValue = sampleOverview();
  List<ResearchEntry> researchValue = [];
  Map<String, ResearchDoc> researchDocs = {};
  List<SkillMeta> skillsValue = [];
  Map<String, SkillDoc> skillDocs = {};
  List<String> inboxValue = [];

  final List<String> calls = [];
  final Map<String, Object> errors = {};

  Future<T> _run<T>(String name, T Function() value, [String? arg]) async {
    calls.add(arg == null ? name : '$name:$arg');
    final error = errors[name];
    if (error != null) throw error;
    return value();
  }

  @override
  Future<Overview> overview() => _run('overview', () => overviewValue);

  @override
  Future<List<ResearchEntry>> research() =>
      _run('research', () => researchValue);

  @override
  Future<ResearchDoc> researchDoc(String path) =>
      _run('researchDoc', () => researchDocs[path]!, path);

  @override
  Future<List<SkillMeta>> skills() => _run('skills', () => skillsValue);

  @override
  Future<SkillDoc> skillDoc(String name) =>
      _run('skillDoc', () => skillDocs[name]!, name);

  @override
  Future<List<String>> inbox() => _run('inbox', () => inboxValue);

  @override
  Future<void> upload(String name, List<int> bytes) => _run('upload', () {
    inboxValue = [...inboxValue, name.toLowerCase().replaceAll(' ', '-')];
  }, name);
}

Overview sampleOverview({List<Finding> findings = const []}) => Overview(
  findings: findings,
  locations: sampleLocations(),
  research: const LibraryCounts(count: 3, tags: 2, topics: 1),
  skills: const LibraryCounts(count: 1, errors: 1),
);

Locations sampleLocations() => const Locations(
  researchRoot: '/repo/storage/data/research',
  skillsRoot: '/repo/storage/data/skills',
  inbox: '/repo/storage/inbox',
  prompt: 'storage/PROMPT.md',
);

ResearchMeta sampleMeta({
  String summary = 'A summary.',
  String kind = 'note',
  String status = 'current',
  String verified = 'human',
  List<String> tags = const ['ai'],
}) => ResearchMeta(
  summary: summary,
  kind: kind,
  status: status,
  verified: verified,
  date: '2026-01-02',
  producedBy: 'claude',
  tags: tags,
  sources: const ['https://example.com'],
);
