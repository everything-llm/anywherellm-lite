import 'package:flutter_test/flutter_test.dart';
import 'package:everything/core/copy.dart';
import 'package:everything/core/models.dart';

void main() {
  group('paths', () {
    test('areaOf is the first segment or (root)', () {
      expect(areaOf('ai/x.md'), 'ai');
      expect(areaOf('a/b/c.md'), 'a');
      expect(areaOf('x.md'), '(root)');
    });

    test('stem drops the directory and one .md', () {
      expect(stem('ai/some-note.md'), 'some-note');
      expect(stem('plain'), 'plain');
      expect(stem('a/b.md.md'), 'b.md');
    });

    test('groupBy keeps first-seen order', () {
      final groups = groupBy(['b1', 'a1', 'b2'], (s) => s[0]);
      expect(groups.keys, ['b', 'a']);
      expect(groups['b'], ['b1', 'b2']);
    });
  });

  group('badges', () {
    test('status is ok only when current', () {
      expect(statusBadge('current').kind, BadgeKind.ok);
      expect(statusBadge('stale').kind, BadgeKind.warn);
    });

    test('verified none reads unverified', () {
      expect(verifiedBadge('none').text, 'unverified');
      expect(verifiedBadge('none').kind, BadgeKind.warn);
      expect(verifiedBadge('human').kind, BadgeKind.ok);
    });
  });

  group('library counts', () {
    test('the line counts documents, tags and topics', () {
      const counts = LibraryCounts(count: 3, tags: 2, topics: 1);
      expect(
        countsLine(counts, 'document', 'documents'),
        '3 documents, 2 tags, 1 topic',
      );
      expect(
        countsLine(const LibraryCounts(count: 1), 'skill', 'skills'),
        '1 skill, 0 tags, 0 topics',
      );
    });

    test('the badges are errors then warnings, and none when clean', () {
      final badges = checkBadges(const LibraryCounts(errors: 1, warnings: 2));
      expect(badges.map((b) => b.text), ['1 error', '2 warnings']);
      expect(badges.map((b) => b.kind), [BadgeKind.bad, BadgeKind.warn]);
      expect(checkBadges(const LibraryCounts()), isEmpty);
    });
  });

  group('research trust', () {
    test('no warning for a current, verified document', () {
      expect(researchTrustWarning(sampleMeta()), isNull);
    });

    test('warns for a stale status', () {
      expect(
        researchTrustWarning(sampleMeta(status: 'stale')),
        'Its status is stale and it is verified: human.',
      );
    });

    test('warns for an unverified document', () {
      expect(
        researchTrustWarning(sampleMeta(verified: 'none')),
        'Its status is current and it is unverified.',
      );
    });
  });

  test('front matter help names the library to check', () {
    expect(
      frontMatterHelp('research'),
      'Run nils research check for the reason.',
    );
    expect(frontMatterHelp('skills'), 'Run nils skills check for the reason.');
  });

  group('staged files', () {
    test('an upload over the server limit is refused', () {
      const limits = Limits.fallback;
      expect(uploadProblem(limits.upload, limits), isNull);
      expect(uploadProblem(limits.upload + 1, limits), 'the file is over 2 MB');
    });

    test('the upload text follows the limit the server sent', () {
      const limits = Limits(upload: 1500000);
      expect(uploadProblem(1500001, limits), 'the file is over 1.5 MB');
    });
  });
}

ResearchMeta sampleMeta({
  String status = 'current',
  String verified = 'human',
}) => ResearchMeta(
  summary: 'A summary.',
  kind: 'note',
  status: status,
  verified: verified,
  date: '2026-01-02',
  producedBy: 'claude',
  tags: const ['ai'],
  sources: const ['https://example.com'],
);
