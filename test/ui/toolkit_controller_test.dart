import 'package:anywherellm/core/errors.dart';
import 'package:anywherellm/core/schedule.dart';
import 'package:anywherellm/core/toolkit.dart';
import 'package:anywherellm/ui/state/memory_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import '../support/fake_toolkit.dart';
import '../support/rig.dart';

const _odd = FormatException('odd');
const _down = ApiException('The bridge is down.');

/// A rig over a toolkit serving [served], with its features read.
Future<Rig> _rig(FakeToolkit toolkit) async {
  final rig = Rig(
    llm: planningServer(),
    toolkitServer: toolkit,
    connection: sampleConnection,
  );
  addTearDown(rig.dispose);
  await rig.start();
  await pumpEventQueue();
  return rig;
}

FakeToolkit _toolkit() => FakeToolkit()
  ..served = {
    ToolkitFeature.jobs,
    ToolkitFeature.jobsWrite,
    ToolkitFeature.memories,
  }
  ..jobs = const [
    ScheduledJob(id: '1', name: 'Digest', prompt: 'p', cron: '0 6 * * *'),
  ];

void main() {
  group('a change that fails oddly', () {
    test('leaves the toolkit free for the next', () async {
      final server = _toolkit()..errors['setJobEnabled'] = _odd;
      final rig = await _rig(server);
      await expectLater(
        rig.toolkit.setEnabled('1', false),
        throwsFormatException,
      );
      expect(rig.toolkit.busy, isFalse);
      server.errors.remove('setJobEnabled');
      expect(await rig.toolkit.setEnabled('1', false), isTrue);
    });

    test('a read that fails oddly can be asked again', () async {
      final server = _toolkit()..errors['scheduledJobs'] = _odd;
      final rig = await _rig(server);
      await expectLater(rig.toolkit.readJobs(), throwsFormatException);
      server.errors.remove('scheduledJobs');
      await rig.toolkit.readJobs(again: true);
      expect(rig.toolkit.jobs, hasLength(1));
    });
  });

  group('why a change failed', () {
    test('goes when the jobs are read again', () async {
      final server = _toolkit()..errors['setJobEnabled'] = _down;
      final rig = await _rig(server);
      expect(await rig.toolkit.setEnabled('1', false), isFalse);
      expect(rig.toolkit.changeProblem, isNotNull);
      await rig.toolkit.readJobs(again: true);
      expect(rig.toolkit.changeProblem, isNull);
    });

    test('goes on clearChangeProblem', () async {
      final server = _toolkit()..errors['setJobEnabled'] = _down;
      final rig = await _rig(server);
      await rig.toolkit.setEnabled('1', false);
      rig.toolkit.clearChangeProblem();
      expect(rig.toolkit.changeProblem, isNull);
    });
  });

  group('saved memories', () {
    test('a change that fails oddly leaves them free for the next', () async {
      final server = _toolkit()..errors['addMemory'] = _odd;
      final rig = await _rig(server);
      final memory = MemoryController(server, rig.settings, rig.chat);
      addTearDown(memory.dispose);
      await memory.read();
      await expectLater(
        memory.add('Likes tea', global: true),
        throwsFormatException,
      );
      expect(memory.busy, isFalse);
      server.errors.remove('addMemory');
      expect(await memory.add('Likes tea', global: true), isTrue);
    });

    test('a read that fails oddly is not left loading', () async {
      final server = _toolkit()..errors['memorySwitches'] = _odd;
      final rig = await _rig(server);
      final memory = MemoryController(server, rig.settings, rig.chat);
      addTearDown(memory.dispose);
      await expectLater(memory.read(), throwsFormatException);
      expect(memory.loading, isFalse);
    });
  });
}
