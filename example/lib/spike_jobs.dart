import 'package:dozeless/dozeless.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'spike_db.dart';
import 'spike_row.dart';

const spikeJobId = 'spike';
const slowJobId = 'slow';
const spikeInterval = Duration(minutes: 1);
const slowInterval = Duration(minutes: 5);

/// Feasibility job (spec §9): every minute, take a location and write a row.
@pragma('vm:entry-point')
Future<void> spikeJob(JobContext ctx) async {
  final startedAt = DateTime.now().millisecondsSinceEpoch;
  double? lat, lon, accuracy;
  int? fixAgeMs;
  var status = 'OK';
  String? error;
  try {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
    );
    (lat, lon, accuracy) = (p.latitude, p.longitude, p.accuracy);
    fixAgeMs = DateTime.now().difference(p.timestamp).inMilliseconds;
  } catch (e) {
    error = 'current: $e';
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) {
        status = 'FAILED';
      } else {
        (lat, lon, accuracy) = (last.latitude, last.longitude, last.accuracy);
        fixAgeMs = DateTime.now().difference(last.timestamp).inMilliseconds;
        status = 'LAST_KNOWN';
      }
    } catch (e2) {
      status = 'FAILED';
      error = '$error; last: $e2';
    }
  }
  await _save(ctx, startedAt,
      lat: lat, lon: lon, accuracy: accuracy, fixAgeMs: fixAgeMs, status: status, error: error);
}

/// Wake-lock test (spec §9): a job that deliberately awaits 20 seconds.
@pragma('vm:entry-point')
Future<void> slowJob(JobContext ctx) async {
  final startedAt = DateTime.now().millisecondsSinceEpoch;
  await Future<void>.delayed(const Duration(seconds: 20));
  await _save(ctx, startedAt, status: 'SLOW');
}

Future<void> _save(
  JobContext ctx,
  int startedAt, {
  double? lat,
  double? lon,
  double? accuracy,
  int? fixAgeMs,
  required String status,
  String? error,
}) async {
  final row = SpikeRow(
    jobId: ctx.jobId,
    trigger: ctx.trigger.name,
    scheduledAt: ctx.scheduledAt.millisecondsSinceEpoch,
    firedAt: ctx.firedAt.millisecondsSinceEpoch,
    delayMs: ctx.delayMs,
    startedAt: startedAt,
    finishedAt: DateTime.now().millisecondsSinceEpoch,
    lat: lat,
    lon: lon,
    accuracyM: accuracy,
    fixAgeMs: fixAgeMs,
    locationStatus: status,
    deviceIdle: ctx.device.deviceIdle,
    interactive: ctx.device.interactive,
    standbyBucket: ctx.device.standbyBucket,
    mode: ctx.mode.name,
    batteryUnrestricted: ctx.prerequisites.batteryUnrestricted,
    events: ctx.systemEvents.map((e) => e.type).join(','),
    error: error,
  );
  await SpikeDb.insert(row);
  debugPrint('DOZELESS_ROW job=${row.jobId} trigger=${row.trigger} delayMs=${row.delayMs} '
      'durMs=${row.finishedAt - row.startedAt} idle=${row.deviceIdle} loc=${row.locationStatus} '
      'fixAgeS=${row.fixAgeMs == null ? '-' : row.fixAgeMs! ~/ 1000} events=${row.events}');
}

Future<void> startSpike() async {
  await Dozeless.schedule(
    id: spikeJobId,
    callback: spikeJob,
    every: spikeInterval,
    requires: {Prereq.location, Prereq.backgroundLocation},
  );
  await Dozeless.schedule(id: slowJobId, callback: slowJob, every: slowInterval);
}

Future<void> stopSpike() async {
  await Dozeless.cancel(spikeJobId);
  await Dozeless.cancel(slowJobId);
}
