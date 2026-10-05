// Grouping, badges and wording, kept in one place so every page says the same things.

import 'models.dart';

/// The group for a skill with no topic.
const unclassified = 'unclassified';

enum BadgeKind { plain, ok, warn, bad, accent }

class BadgeSpec {
  const BadgeSpec(this.text, [this.kind = BadgeKind.plain]);
  final String text;
  final BadgeKind kind;
}

// ---- badges ----------------------------------------------------------------------------------

BadgeSpec statusBadge(String status) =>
    BadgeSpec(status, status == 'current' ? BadgeKind.ok : BadgeKind.warn);

BadgeSpec verifiedBadge(String verified) => verified == 'none'
    ? const BadgeSpec('unverified', BadgeKind.warn)
    : BadgeSpec(verified, BadgeKind.ok);

BadgeSpec severityBadge(String severity) =>
    BadgeSpec(severity, severity == 'error' ? BadgeKind.bad : BadgeKind.warn);

/// `1 item`, `3 items`.
String plural(int count, String one, String many) =>
    '$count ${count == 1 ? one : many}';

/// `3 documents, 2 tags, 1 topic`: what a library holds.
String countsLine(LibraryCounts counts, String one, String many) =>
    '${plural(counts.count, one, many)}, '
    '${plural(counts.tags, 'tag', 'tags')}, '
    '${plural(counts.topics, 'topic', 'topics')}';

/// What a library's last check found, as badges: errors, then warnings. None when it is clean.
List<BadgeSpec> checkBadges(LibraryCounts counts) => [
  if (counts.errors > 0)
    BadgeSpec(plural(counts.errors, 'error', 'errors'), BadgeKind.bad),
  if (counts.warnings > 0)
    BadgeSpec(plural(counts.warnings, 'warning', 'warnings'), BadgeKind.warn),
];

/// `1 thing to look at`, for a badge's tooltip and its screen reader label.
String findingsNote(int count) =>
    '${plural(count, 'thing', 'things')} to look at';

// ---- grouping --------------------------------------------------------------------------------

/// The first path segment, or `(root)` for a file at the top.
String areaOf(String path) =>
    path.contains('/') ? path.split('/').first : '(root)';

final _markdownSuffix = RegExp(r'\.md$');

String stem(String path) =>
    path.split('/').last.replaceFirst(_markdownSuffix, '');

/// Groups [items] by [key], keeping the order in which each group first appears.
Map<String, List<T>> groupBy<T>(Iterable<T> items, String Function(T) key) {
  final groups = <String, List<T>>{};
  for (final item in items) {
    (groups[key(item)] ??= []).add(item);
  }
  return groups;
}

// ---- documents -------------------------------------------------------------------------------

/// What to do about a document whose front matter could not be read.
String frontMatterHelp(String library) =>
    'Run nils $library check for the reason.';

/// The warning for a document that should not be relied on as it stands, or null.
String? researchTrustWarning(ResearchMeta meta) {
  if (meta.status == 'current' && meta.verified != 'none') return null;
  final verified = meta.verified == 'none'
      ? 'unverified'
      : 'verified: ${meta.verified}';
  return 'Its status is ${meta.status} and it is $verified.';
}

/// The file type shown on a staged file's tile.
String sourceExt(String name) {
  if (!name.contains('.')) return 'FILE';
  final ext = name.split('.').last.toUpperCase();
  return ext.length > 4 ? ext.substring(0, 4) : ext;
}

/// Why a file of [size] bytes cannot be staged, or null.
String? uploadProblem(int size, Limits limits) {
  if (size <= limits.upload) return null;
  final mb = limits.upload / 1000000;
  return 'the file is over ${mb == mb.roundToDouble() ? mb.round() : mb.toStringAsFixed(1)} MB';
}
