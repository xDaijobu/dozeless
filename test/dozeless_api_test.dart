import 'package:dozeless/dozeless.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> topLevelJob(JobContext ctx) async {}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  Object? reply;

  setUp(() {
    calls.clear();
    reply = null;
    Dozeless.callbackHandleOf = (_) => 4242;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(Dozeless.channel, (call) async {
      calls.add(call);
      return reply;
    });
  });

  group('schedule', () {
    test('sends the job spec with sorted prerequisite names', () async {
      await Dozeless.schedule(
        id: 'get',
        callback: topLevelJob,
        every: const Duration(minutes: 5),
        requires: {Prereq.location, Prereq.backgroundLocation},
      );
      expect(calls.single.method, 'schedule');
      expect(calls.single.arguments, {
        'id': 'get',
        'callbackHandle': 4242,
        'everyMs': 300000,
        'timeoutMs': 45000,
        'requires': ['backgroundLocation', 'location'],
      });
    });

    test('rejects a callback without a handle, such as a closure', () async {
      Dozeless.callbackHandleOf = (_) => null;
      await expectLater(
        Dozeless.schedule(id: 'get', callback: (ctx) async {}, every: const Duration(minutes: 5)),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    });

    test('rejects intervals under one minute', () async {
      await expectLater(
        Dozeless.schedule(id: 'get', callback: topLevelJob, every: const Duration(seconds: 59)),
        throwsArgumentError,
      );
    });

    test('rejects timeouts over 50 seconds', () async {
      await expectLater(
        Dozeless.schedule(
          id: 'get',
          callback: topLevelJob,
          every: const Duration(minutes: 5),
          timeout: const Duration(seconds: 51),
        ),
        throwsArgumentError,
      );
    });

    test('rejects ids that cannot go into an alarm URI', () async {
      await expectLater(
        Dozeless.schedule(id: 'get job', callback: topLevelJob, every: const Duration(minutes: 5)),
        throwsArgumentError,
      );
    });
  });

  group('status', () {
    test('parses the native map', () async {
      reply = {'id': 'get', 'mode': 'inexact', 'runCount': 3};
      final s = await Dozeless.status('get');
      expect(s!.mode, JobMode.inexact);
      expect(s.runCount, 3);
      expect(calls.single.arguments, {'id': 'get'});
    });

    test('is null for an unknown job', () async {
      expect(await Dozeless.status('nope'), isNull);
    });
  });

  test('debugFireIn sends the delay in milliseconds', () async {
    await Dozeless.debugFireIn('get', const Duration(seconds: 10));
    expect(calls.single.method, 'debugFireIn');
    expect(calls.single.arguments, {'id': 'get', 'delayMs': 10000});
  });

  test('runNow sends the job id', () async {
    await Dozeless.runNow('get');
    expect(calls.single.method, 'runNow');
    expect(calls.single.arguments, {'id': 'get'});
  });

  test('watchdog debug helpers call the plugin', () async {
    await Dozeless.debugSimulateLostAlarm('get');
    await Dozeless.debugRunWatchdog();
    expect(calls.map((c) => c.method), ['debugSimulateLostAlarm', 'debugRunWatchdog']);
    expect(calls.first.arguments, {'id': 'get'});
  });

  test('checkPrerequisites parses the snapshot', () async {
    reply = {'location': true, 'batteryUnrestricted': false, 'autostartSettingAvailable': true};
    final p = await Dozeless.checkPrerequisites();
    expect(p.location, isTrue);
    expect(p.autostartSettingAvailable, isTrue);
    expect(p.missingFor({Prereq.location}), [Prereq.batteryUnrestricted]);
  });

  test('openSettings sends the setting name and returns the result', () async {
    reply = true;
    expect(await Dozeless.openSettings(Setting.autostart), isTrue);
    expect(calls.single.arguments, {'setting': 'autostart'});
  });

  test('initialize sends the dispatcher and notification text, then reconciles on every resume', () async {
    await Dozeless.initialize(stopNotification: const StopNotification(title: 'T', body: 'B', channelName: 'C'));
    expect(calls.single.method, 'initialize');
    expect(calls.single.arguments, {
      'dispatcherHandle': 4242,
      'notificationTitle': 'T',
      'notificationBody': 'B',
      'notificationChannel': 'C',
    });

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(calls.map((c) => c.method), ['initialize', 'reconcile']);
  });
}
