import 'package:flutter_test/flutter_test.dart';
import 'package:everything/core/models.dart';

void main() {
  test('overview reads counts, findings and the locations block', () {
    final overview = Overview.fromJson({
      'research': {
        'documents': 4,
        'tags': 2,
        'topics': 1,
        'errors': 1,
        'warnings': 2,
      },
      'skills': {
        'count': 3,
        'tags': 0,
        'topics': 0,
        'errors': 0,
        'warnings': 0,
      },
      'findings': [
        {
          'library': 'research',
          'path': 'a.md',
          'message': 'm',
          'severity': 'error',
        },
      ],
      'locations': {
        'research_root': '/r',
        'skills_root': '/s',
        'inbox': '/i',
        'prompt': '/p',
      },
      'limits': {'upload': 40},
    });
    expect(overview.findings.single.severity, 'error');
    expect(overview.locations.researchRoot, '/r');
    expect(overview.locations.prompt, '/p');
    expect(overview.research.count, 4);
    expect(overview.research.warnings, 2);
    expect(overview.skills.count, 3);
    expect(overview.limits.upload, 40);
  });

  test(
    'an overview without findings, counts or limits has none and the fallback',
    () {
      final overview = Overview.fromJson({'locations': <String, dynamic>{}});
      expect(overview.findings, isEmpty);
      expect(overview.research.count, 0);
      expect(overview.skills.count, 0);
      expect(overview.limits.upload, 2000000);
    },
  );

  test('an empty optional string reads as null', () {
    final skill = SkillMeta.fromJson({
      'name': 'n',
      'description': 'd',
      'topic': '',
      'tags': <String>[],
      'added': '',
    });
    expect(skill.topic, isNull);
    expect(skill.added, isNull);
  });

  test('jsonList builds each object and reads null as empty', () {
    expect(
      jsonList([
        {'name': 'a'},
        {'name': 'b'},
      ], (json) => jsonText(json, 'name')),
      ['a', 'b'],
    );
    expect(jsonList<String>(null, (json) => ''), isEmpty);
  });

  test('a locations block without paths has empty ones', () {
    final places = Locations.fromJson({'inbox': '/i'});
    expect(places.inbox, '/i');
    expect(places.researchRoot, '');
  });

  test('a research list entry carries its path and front matter', () {
    final entry = ResearchEntry.fromJson({
      'path': 'ai/x.md',
      'summary': 'S',
      'kind': 'note',
      'status': 'current',
      'verified': 'none',
      'date': '2026-01-02',
      'produced_by': 'me',
      'tags': ['a', 'b'],
      'sources': ['http://x'],
    });
    expect(entry.path, 'ai/x.md');
    expect(entry.meta.producedBy, 'me');
    expect(entry.meta.tags, ['a', 'b']);
    expect(entry.meta.sources, hasLength(1));
  });

  test('a research doc with unreadable front matter has null meta', () {
    final doc = ResearchDoc.fromJson({
      'path': 'x.md',
      'text': 't',
      'meta': null,
    });
    expect(doc.meta, isNull);
    expect(doc.text, 't');
  });

  test('a skill reads a null topic and date', () {
    final skill = SkillMeta.fromJson({
      'name': 'n',
      'description': 'd',
      'topic': null,
      'tags': <String>[],
      'added': null,
    });
    expect(skill.topic, isNull);
    expect(skill.added, isNull);
  });
}
