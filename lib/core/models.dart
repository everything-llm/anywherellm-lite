// What `nils view` prints. Shapes follow src/nils/adapters/library/views.py in the nils repository.

typedef Json = Map<String, dynamic>;

String jsonText(Json json, String key) => (json[key] as String?) ?? '';

/// A string field, or null when it is missing or empty.
String? _optional(Json json, String key) {
  final value = json[key] as String?;
  return value == null || value.isEmpty ? null : value;
}

int _count(Json json, String key) => (json[key] as num?)?.toInt() ?? 0;

List<String> _strings(Json json, String key) =>
    ((json[key] as List<dynamic>?) ?? const []).cast<String>();

/// A nested object built by [build], or null when the key is missing or null.
T? _object<T>(Json json, String key, T Function(Json) build) {
  final value = json[key];
  return value == null ? null : build(value as Json);
}

/// A list of nested objects; a missing or null key is an empty list.
List<T> _objects<T>(Json json, String key, T Function(Json) build) =>
    jsonList(json[key], build);

/// [value] as a list of objects built by [build]; null is an empty list.
List<T> jsonList<T>(Object? value, T Function(Json) build) => [
  for (final item in (value as List<dynamic>?) ?? const []) build(item as Json),
];

class Finding {
  const Finding({
    required this.library,
    required this.path,
    required this.message,
    required this.severity,
  });

  factory Finding.fromJson(Json json) => Finding(
    library: jsonText(json, 'library'),
    path: jsonText(json, 'path'),
    message: jsonText(json, 'message'),
    severity: jsonText(json, 'severity'),
  );

  final String library;
  final String path;
  final String message;
  final String severity;
}

/// Where nils keeps things.
class Locations {
  const Locations({
    this.researchRoot = '',
    this.skillsRoot = '',
    this.inbox = '',
    this.prompt = '',
  });

  factory Locations.fromJson(Json json) => Locations(
    researchRoot: jsonText(json, 'research_root'),
    skillsRoot: jsonText(json, 'skills_root'),
    inbox: jsonText(json, 'inbox'),
    prompt: jsonText(json, 'prompt'),
  );

  final String researchRoot;
  final String skillsRoot;
  final String inbox;
  final String prompt;
}

/// The sizes nils accepts. nils reports them so the app never drifts from it.
class Limits {
  const Limits({required this.upload});

  factory Limits.fromJson(Json json) => Limits(upload: _count(json, 'upload'));

  /// What nils allowed before it reported limits.
  static const fallback = Limits(upload: 2000000);

  /// The most bytes of one staged file.
  final int upload;
}

/// What a library holds and what its last check found.
class LibraryCounts {
  const LibraryCounts({
    this.count = 0,
    this.tags = 0,
    this.topics = 0,
    this.errors = 0,
    this.warnings = 0,
  });

  /// nils names the count `documents` for research and `count` for skills.
  factory LibraryCounts.fromJson(Json json) => LibraryCounts(
    count: _count(json, json.containsKey('documents') ? 'documents' : 'count'),
    tags: _count(json, 'tags'),
    topics: _count(json, 'topics'),
    errors: _count(json, 'errors'),
    warnings: _count(json, 'warnings'),
  );

  final int count;
  final int tags;
  final int topics;
  final int errors;
  final int warnings;
}

class Overview {
  const Overview({
    required this.findings,
    required this.locations,
    this.research = const LibraryCounts(),
    this.skills = const LibraryCounts(),
    this.limits = Limits.fallback,
  });

  factory Overview.fromJson(Json json) => Overview(
    findings: _objects(json, 'findings', Finding.fromJson),
    locations: Locations.fromJson(json['locations'] as Json),
    research:
        _object(json, 'research', LibraryCounts.fromJson) ??
        const LibraryCounts(),
    skills:
        _object(json, 'skills', LibraryCounts.fromJson) ??
        const LibraryCounts(),
    limits: _object(json, 'limits', Limits.fromJson) ?? Limits.fallback,
  );

  final List<Finding> findings;
  final Locations locations;
  final LibraryCounts research;
  final LibraryCounts skills;
  final Limits limits;
}

class ResearchMeta {
  const ResearchMeta({
    required this.summary,
    required this.kind,
    required this.status,
    required this.verified,
    required this.date,
    required this.producedBy,
    required this.tags,
    required this.sources,
  });

  factory ResearchMeta.fromJson(Json json) => ResearchMeta(
    summary: jsonText(json, 'summary'),
    kind: jsonText(json, 'kind'),
    status: jsonText(json, 'status'),
    verified: jsonText(json, 'verified'),
    date: jsonText(json, 'date'),
    producedBy: jsonText(json, 'produced_by'),
    tags: _strings(json, 'tags'),
    sources: _strings(json, 'sources'),
  );

  final String summary;
  final String kind;
  final String status;
  final String verified;
  final String date;
  final String producedBy;
  final List<String> tags;
  final List<String> sources;
}

class ResearchEntry {
  const ResearchEntry({required this.path, required this.meta});

  /// The list sends the path and the front matter side by side.
  factory ResearchEntry.fromJson(Json json) => ResearchEntry(
    path: jsonText(json, 'path'),
    meta: ResearchMeta.fromJson(json),
  );

  final String path;
  final ResearchMeta meta;
}

class ResearchDoc {
  const ResearchDoc({required this.path, required this.text, this.meta});

  factory ResearchDoc.fromJson(Json json) => ResearchDoc(
    path: jsonText(json, 'path'),
    text: jsonText(json, 'text'),
    meta: _object(json, 'meta', ResearchMeta.fromJson),
  );

  final String path;
  final String text;

  /// Null when the front matter could not be read.
  final ResearchMeta? meta;
}

class SkillMeta {
  const SkillMeta({
    required this.name,
    required this.description,
    required this.tags,
    this.topic,
    this.added,
  });

  factory SkillMeta.fromJson(Json json) => SkillMeta(
    name: jsonText(json, 'name'),
    description: jsonText(json, 'description'),
    topic: _optional(json, 'topic'),
    tags: _strings(json, 'tags'),
    added: _optional(json, 'added'),
  );

  final String name;
  final String description;
  final String? topic;
  final List<String> tags;
  final String? added;
}

class SkillDoc {
  const SkillDoc({required this.name, required this.text, this.meta});

  factory SkillDoc.fromJson(Json json) => SkillDoc(
    name: jsonText(json, 'name'),
    text: jsonText(json, 'text'),
    meta: _object(json, 'meta', SkillMeta.fromJson),
  );

  final String name;
  final String text;
  final SkillMeta? meta;
}
