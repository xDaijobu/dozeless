import 'package:dozeless_example/spike_row.dart';
import 'package:dozeless_example/spike_stats.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime(2026, 10, 29, 10);

SpikeRow row(int minute,
    {int delayMs = 1000, String jobId = 'spike', String trigger = 'alarm', double? lat = -6.2, int? fixAgeMs = 3000}) {
  final firedAt = t0.add(Duration(minutes: minute)).millisecondsSinceEpoch;
  return SpikeRow(
    jobId: jobId,
    trigger: trigger,
    scheduledAt: firedAt - delayMs,
    firedAt: firedAt,
    delayMs: delayMs,
    startedAt: firedAt,
    finishedAt: firedAt + 2000,
    lat: lat,
    lon: lat == null ? null : 106.8,
    fixAgeMs: lat == null ? null : fixAgeMs,
    locationStatus: lat == null ? 'FAILED' : 'OK',
    deviceIdle: true,
    interactive: false,
    standbyBucket: 'active',
    mode: 'exact',
    batteryUnrestricted: true,
  );
}

SpikeStats stats(List<SpikeRow> rows) => SpikeStats.compute(
      rows,
      jobId: 'spike',
      interval: const Duration(minutes: 1),
      from: t0,
      to: t0.add(const Duration(minutes: 90)),
    );

void main() {
  test('a run every minute for 90 minutes passes', () {
    final s = stats([for (var m = 0; m < 90; m++) row(m)]);
    expect(s.expected, 90);
    expect(s.ran, 90);
    expect(s.medianDelayMs, 1000);
    expect(s.passes, isTrue);
  });

  test('fewer than 95% of the runs fails', () {
    final s = stats([for (var m = 0; m < 85; m++) row(m)]);
    expect(s.ranRatio, closeTo(0.944, 0.001));
    expect(s.passes, isFalse);
  });

  test('a median delay of 10 seconds or more fails', () {
    expect(stats([for (var m = 0; m < 90; m++) row(m, delayMs: 10000)]).passes, isFalse);
  });

  test('a row without location fails', () {
    expect(stats([for (var m = 0; m < 90; m++) row(m, lat: m == 40 ? null : -6.2)]).passes, isFalse);
  });

  test('median of an even count averages the middle two', () {
    expect(stats([row(0, delayMs: 1000), row(1, delayMs: 3000)]).medianDelayMs, 2000);
  });

  test('ignores other jobs, non-alarm triggers and rows outside the window', () {
    final s = stats([
      row(0),
      row(1, jobId: 'slow'),
      row(2, trigger: 'manual'),
      row(-1),
      row(90),
    ]);
    expect(s.ran, 1);
  });

  test('a cached fix older than two intervals counts as located but not fresh', () {
    final s = stats([row(0), row(1, fixAgeMs: 120000), row(2, fixAgeMs: 119999), row(3, lat: null)]);
    expect(s.withLocation, 3);
    expect(s.withFreshLocation, 2);
  });
}
