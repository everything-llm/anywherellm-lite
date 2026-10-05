@Tags(['live'])
library;

import 'dart:io';

import 'package:everything/adapters/cli_nils_api.dart';
import 'package:everything/adapters/nils_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final given = Platform.environment['NILS_REPO'];
  final repo = given != null && given.isNotEmpty
      ? Directory(given)
      : NilsCommand.findRepo([Directory.current]);
  final api = repo == null ? null : CliNilsApi(NilsCommand.forRepo(repo));

  test('the real nils answers every read', () async {
    final overview = await api!.overview();
    expect(overview.locations.researchRoot, isNotEmpty);
    expect(overview.limits.upload, greaterThan(0));
    final research = await api.research();
    expect(research.length, overview.research.count);
    if (research.isNotEmpty) {
      expect((await api.researchDoc(research.first.path)).text, isNotEmpty);
    }
    final skills = await api.skills();
    if (skills.isNotEmpty) {
      expect((await api.skillDoc(skills.first.name)).text, isNotEmpty);
    }
    expect(await api.inbox(), isA<List<String>>());
  }, skip: repo == null ? 'no nils checkout found; set NILS_REPO' : false);

  test('a missing document is nils\'s own refusal', () async {
    await expectLater(
      api!.researchDoc('no/such.md'),
      throwsA(
        isA<Exception>().having((e) => '$e', 'message', 'no such document'),
      ),
    );
  }, skip: repo == null ? 'no nils checkout found; set NILS_REPO' : false);
}
