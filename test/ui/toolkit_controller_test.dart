import 'package:anywherellm/core/asks.dart';
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
Future<Rig> _rig(FakeToolkit toolkit, {WidgetTester? tester}) async {
  final rig = Rig(
    llm: planningServer(),
    toolkitServer: toolkit,
    connection: sampleConnection,
  );
  addTearDown(rig.dispose);
  await rig.start();
  await (tester?.pump() ?? pumpEventQueue());
  return rig;
}

FakeToolkit _toolkit() => FakeToolkit()
  ..served = {
    ToolkitFeature.jobs,
    ToolkitFeature.jobsWrite,
    ToolkitFeature.asks,
    ToolkitFeature.memories,
  }
  ..jobs = const [
    ScheduledJob(id: '1', name: 'Digest', prompt: 'p', cron: '0 6 * * *'),
  ]
  ..allowed = [
    const AllowedOrigin('http://a:1'),
    const AllowedOrigin('http://b:2'),
  ];

int _reads(FakeToolkit toolkit) =>
    toolkit.calls.where((c) => c == 'allowedOrigins').length;

void main() {
  group('forgetting an allowed address', () {
    test('that fails reads the list again', () async {
      final server = _toolkit();
      final rig = await _rig(server);
      await rig.toolkit.readAllowed();
      server.errors['forgetOrigin'] = _down;
      // Another device removed one meanwhile.
      server.allowed = [const AllowedOrigin('http://b:2')];
      await rig.toolkit.forgetOrigin('http://b:2');
      expect(_reads(server), 2);
      expect(rig.toolkit.allowed!.map((o) => o.origin), ['http://b:2']);
      expect(rig.toolkit.changeProblem?.text, _down.message);
    });

    test('shows the list it could not read again as well as why', () async {
      final server = _toolkit();
      final rig = await _rig(server);
      await rig.toolkit.readAllowed();
      server.errors['forgetOrigin'] = _down;
      server.errors['allowedOrigins'] = const ApiException('Refused.');
      await rig.toolkit.forgetOrigin('http://b:2');
      expect(rig.toolkit.allowedProblem?.text, 'Refused.');
      expect(rig.toolkit.changeProblem?.text, _down.message);
    });
  });

  group('the allowed addresses', () {
    testWidgets('are read again once asked for after a failed read', (
      tester,
    ) async {
      final server = _toolkit()..errors['allowedOrigins'] = _down;
      final rig = await _rig(server, tester: tester);
      await rig.toolkit.readAllowed();
      expect(rig.toolkit.allowedProblem, isNotNull);
      server.errors.remove('allowedOrigins');
      // A page that builds again does not ask again, or a failing read would never stop.
      rig.toolkit.wantAllowed();
      TestWidgetsFlutterBinding.instance.scheduleFrame();
      await tester.pump();
      expect(rig.toolkit.allowedProblem, isNotNull);
      rig.toolkit.wantAllowed(retry: true);
      TestWidgetsFlutterBinding.instance.scheduleFrame();
      await tester.pump();
      await tester.pump();
      expect(rig.toolkit.allowed, hasLength(2));
      expect(rig.toolkit.allowedProblem, isNull);
    });
  });

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
