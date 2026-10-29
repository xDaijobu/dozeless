import 'dart:isolate';
import 'dart:ui';

import 'package:dozeless/dozeless.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _portName = 'dozeless_it';
const _ids = ['it_ok', 'it_fail', 'it_slow'];

@pragma('vm:entry-point')
Future<void> okJob(JobContext ctx) async {
  IsolateNameServer.lookupPortByName(_portName)?.send({'id': ctx.jobId, 'trigger': ctx.trigger.name});
}

@pragma('vm:entry-point')
Future<void> failingJob(JobContext ctx) async => throw StateError('boom');

@pragma('vm:entry-point')
Future<void> slowJob(JobContext ctx) async => Future<void>.delayed(const Duration(seconds: 8));

Future<JobStatus> waitForStatus(String id, bool Function(JobStatus s) done) async {
  for (var i = 0; i < 60; i++) {
    final s = await Dozeless.status(id);
    if (s != null && done(s)) return s;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw TestFailure('status of $id never matched');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late ReceivePort port;
  late Stream<Object?> messages;

  /// Waits for a run of [id] with [trigger]; runs left over from an earlier, killed test run are skipped.
  Future<Map<Object?, Object?>> nextRun(String id, String trigger, Duration timeout) => messages
      .map((m) => m! as Map<Object?, Object?>)
      .firstWhere((m) => m['id'] == id && m['trigger'] == trigger)
      .timeout(timeout);

  setUp(() async {
    IsolateNameServer.removePortNameMapping(_portName);
    port = ReceivePort();
    IsolateNameServer.registerPortWithName(port.sendPort, _portName);
    messages = port.asBroadcastStream();
    // A killed run never reaches tearDown, so start from a clean slate.
    for (final id in _ids) {
      await Dozeless.cancel(id);
    }
    await Dozeless.initialize();
    if (!(await Dozeless.checkPrerequisites()).batteryUnrestricted) {
      fail('Battery is not unrestricted, so every job would stop. Run: '
          'adb shell dumpsys deviceidle whitelist +io.github.xdaijobu.dozeless_example '
          'and use flutter test --no-uninstall');
    }
  });

  tearDown(() async {
    for (final id in _ids) {
      await Dozeless.cancel(id);
    }
    port.close();
  });

  testWidgets('runNow runs the callback in the background engine', (tester) async {
    await Dozeless.schedule(id: 'it_ok', callback: okJob, every: const Duration(minutes: 15));
    await Dozeless.runNow('it_ok');
    await nextRun('it_ok', 'manual', const Duration(seconds: 30));
    final s = await waitForStatus('it_ok', (s) => s.runCount == 1);
    expect(s.lastError, isNull);
  });

  testWidgets('an alarm fires the callback and chains the next alarm', (tester) async {
    await Dozeless.schedule(id: 'it_ok', callback: okJob, every: const Duration(minutes: 15));
    await Dozeless.debugFireIn('it_ok', const Duration(seconds: 5));
    await nextRun('it_ok', 'alarm', const Duration(seconds: 90));
    final s = await waitForStatus('it_ok', (s) => s.runCount == 1);
    expect(s.nextRunAt!.isAfter(DateTime.now().add(const Duration(minutes: 14))), isTrue);
  });

  testWidgets('a throwing job records JOB_FAILED and keeps the chain', (tester) async {
    await Dozeless.schedule(id: 'it_fail', callback: failingJob, every: const Duration(minutes: 15));
    await Dozeless.debugFireIn('it_fail', const Duration(seconds: 5));
    final s = await waitForStatus('it_fail', (s) => s.runCount == 1);
    expect(s.lastError, startsWith('JOB_FAILED'));
    expect(s.nextRunAt!.isAfter(DateTime.now().add(const Duration(minutes: 14))), isTrue);
  });

  testWidgets('a job past its timeout records JOB_TIMEOUT', (tester) async {
    await Dozeless.schedule(
      id: 'it_slow',
      callback: slowJob,
      every: const Duration(minutes: 15),
      timeout: const Duration(seconds: 3),
    );
    await Dozeless.runNow('it_slow');
    final s = await waitForStatus('it_slow', (s) => s.runCount == 1);
    expect(s.lastError, 'JOB_TIMEOUT');
    expect(s.lastDurationMs, lessThan(6000));
  });

  testWidgets('the watchdog re-runs a job whose alarm was lost', (tester) async {
    await Dozeless.schedule(id: 'it_ok', callback: okJob, every: const Duration(minutes: 15));
    await Dozeless.debugSimulateLostAlarm('it_ok');
    await Dozeless.debugRunWatchdog();
    await nextRun('it_ok', 'watchdog', const Duration(seconds: 90));
  });
}
