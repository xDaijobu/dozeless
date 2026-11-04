import 'package:dozeless/dozeless.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> sampleContext() => {
      'jobId': 'get',
      'trigger': 'boot',
      'scheduledAt': 1700000000000,
      'firedAt': 1700000004500,
      'delayMs': 4500,
      'timeoutMs': 45000,
      'mode': 'inexact',
      'lastRunAt': 1699999940000,
      'lastError': 'JOB_TIMEOUT',
      'stoppedAt': null,
      'boot': {'bootCount': 12, 'bootTime': 1699990000000, 'firstJobSinceBoot': true},
      'systemEvents': [
        {
          'seq': 7,
          'type': 'timeChanged',
          'at': 1699999990000,
          'data': {'jumpMs': -3600000, 'autoTime': false},
        },
      ],
      'prerequisites': {
        'location': true,
        'backgroundLocation': false,
        'batteryUnrestricted': true,
        'backgroundRestricted': false,
        'exactAlarm': true,
        'notification': false,
        'autostartSettingAvailable': true,
      },
      'device': {
        'deviceId': 'abc123',
        'deviceIdle': true,
        'interactive': false,
        'powerSaveMode': false,
        'standbyBucket': 'active',
        'autoTime': false,
        'timezone': 'Asia/Jakarta',
        'cellLevel': 3,
        'wifiLevel': null,
      },
    };

void main() {
  group('JobContext.fromMap', () {
    test('parses every field the plugin sends', () {
      final ctx = JobContext.fromMap(sampleContext());
      expect(ctx.jobId, 'get');
      expect(ctx.trigger, JobTrigger.boot);
      expect(ctx.delayMs, 4500);
      expect(ctx.firedAt.millisecondsSinceEpoch, 1700000004500);
      expect(ctx.deadline.millisecondsSinceEpoch, 1700000004500 + 45000);
      expect(ctx.mode, JobMode.inexact);
      expect(ctx.lastError, 'JOB_TIMEOUT');
      expect(ctx.stoppedAt, isNull);
      expect(ctx.boot.bootCount, 12);
      expect(ctx.boot.firstJobSinceBoot, isTrue);
      expect(ctx.systemEvents.single.type, 'timeChanged');
      expect(ctx.systemEvents.single.data['jumpMs'], -3600000);
      expect(ctx.prerequisites.backgroundLocation, isFalse);
      expect(ctx.prerequisites.autostartSettingAvailable, isTrue);
      expect(ctx.device.deviceIdle, isTrue);
      expect(ctx.device.timezone, 'Asia/Jakarta');
      expect(ctx.device.cellLevel, 3);
      expect(ctx.device.wifiLevel, isNull);
    });

    test('an unknown trigger falls back to alarm instead of throwing', () {
      expect(JobContext.fromMap({...sampleContext(), 'trigger': 'somethingNew'}).trigger, JobTrigger.alarm);
    });

    test('missing sections give safe defaults', () {
      final ctx = JobContext.fromMap({'jobId': 'x', 'trigger': 'manual', 'scheduledAt': 1, 'firedAt': 2});
      expect(ctx.systemEvents, isEmpty);
      expect(ctx.prerequisites.batteryUnrestricted, isFalse);
      expect(ctx.boot.bootCount, isNull);
      expect(ctx.timeout, const Duration(seconds: 45));
    });
  });

  group('PrerequisiteStatus.missingFor', () {
    const allOk = PrerequisiteStatus(
      location: true,
      backgroundLocation: true,
      batteryUnrestricted: true,
      backgroundRestricted: false,
      exactAlarm: true,
      notification: true,
    );

    test('nothing is missing when everything is granted', () {
      expect(allOk.missingFor({Prereq.location, Prereq.backgroundLocation}), isEmpty);
    });

    test('battery and background restriction count even when not requested', () {
      const s = PrerequisiteStatus(
        location: true,
        backgroundLocation: true,
        batteryUnrestricted: false,
        backgroundRestricted: true,
        exactAlarm: true,
        notification: true,
      );
      expect(s.missingFor({}), [Prereq.batteryUnrestricted, Prereq.notBackgroundRestricted]);
    });

    test('exact alarm and notification never block', () {
      const s = PrerequisiteStatus(
        location: true,
        backgroundLocation: true,
        batteryUnrestricted: true,
        backgroundRestricted: false,
        exactAlarm: false,
        notification: false,
      );
      expect(s.missingFor(Prereq.values.toSet()), isEmpty);
    });
  });

  test('JobStatus.fromMap parses status and drops unknown prerequisite names', () {
    final s = JobStatus.fromMap({
      'id': 'get',
      'mode': 'stopped',
      'nextRunAt': null,
      'lastRunAt': 1700000000000,
      'lastError': null,
      'lastTrigger': 'watchdog',
      'runCount': 5,
      'skippedBusyCount': 1,
      'missing': ['backgroundLocation', 'bogus'],
      'stoppedAt': 1700000001000,
    });
    expect(s.mode, JobMode.stopped);
    expect(s.lastTrigger, JobTrigger.watchdog);
    expect(s.missing, [Prereq.backgroundLocation]);
    expect(s.nextRunAt, isNull);
    expect(s.runCount, 5);
    expect(s.stoppedAt!.millisecondsSinceEpoch, 1700000001000);
  });

  test('StopNotification defaults to English text', () {
    expect(const StopNotification().toMap(), {
      'notificationTitle': 'Background work stopped',
      'notificationBody': 'Open the app to fix its permissions or battery settings.',
      'notificationChannel': 'Background status',
    });
  });
}
