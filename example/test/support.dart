import 'package:dozeless/dozeless.dart';
import 'package:dozeless_example/spike_row.dart';
import 'package:dozeless_example/ui/model.dart';
import 'package:dozeless_example/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A run fired [ago] before now.
SpikeRow runRow({
  Duration ago = Duration.zero,
  DateTime? firedAt,
  String jobId = 'spike',
  String trigger = 'alarm',
  int delayMs = 1200,
  int durationMs = 2100,
  String locationStatus = 'OK',
  int? fixAgeMs = 3000,
  double? accuracyM = 12,
  bool deviceIdle = false,
  String standbyBucket = 'active',
  String events = '',
  String? error,
}) {
  final fired = (firedAt ?? DateTime.now().subtract(ago)).millisecondsSinceEpoch;
  final located = locationStatus == 'OK' || locationStatus == 'LAST_KNOWN';
  return SpikeRow(
    jobId: jobId,
    trigger: trigger,
    scheduledAt: fired - delayMs,
    firedAt: fired,
    delayMs: delayMs,
    startedAt: fired,
    finishedAt: fired + durationMs,
    lat: located ? -6.2 : null,
    lon: located ? 106.8 : null,
    accuracyM: located ? accuracyM : null,
    fixAgeMs: located ? fixAgeMs : null,
    locationStatus: locationStatus,
    deviceIdle: deviceIdle,
    interactive: false,
    standbyBucket: standbyBucket,
    mode: 'exact',
    batteryUnrestricted: true,
    events: events,
    error: error,
  );
}

PrerequisiteStatus prereqs({
  bool location = true,
  bool backgroundLocation = true,
  bool batteryUnrestricted = true,
  bool backgroundRestricted = false,
  bool exactAlarm = true,
  bool notification = true,
  bool autostartSettingAvailable = false,
  bool forceStopGuard = false,
  bool forceStopGuardAvailable = false,
}) =>
    PrerequisiteStatus(
      location: location,
      backgroundLocation: backgroundLocation,
      batteryUnrestricted: batteryUnrestricted,
      backgroundRestricted: backgroundRestricted,
      exactAlarm: exactAlarm,
      notification: notification,
      autostartSettingAvailable: autostartSettingAvailable,
      forceStopGuard: forceStopGuard,
      forceStopGuardAvailable: forceStopGuardAvailable,
    );

/// Puts [child] in a themed scaffold, the way the app shows it.
Widget themed(Widget child) => MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [child])),
    );

/// A 1080x2400 phone at 420 dpi: 411x914 logical pixels.
void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

/// Records every call instead of talking to the platform.
class FakeBackend implements ExampleBackend {
  FakeBackend(this.snapshot);

  Snapshot snapshot;
  bool fixOpens = true;
  final calls = <Object>[];

  @override
  Future<Snapshot> load() async => snapshot;

  @override
  Future<void> startJobs() async => calls.add('start');

  @override
  Future<void> stopJobs() async => calls.add('stop');

  @override
  Future<bool> fix(SetupAction action) async {
    calls.add(action);
    return fixOpens;
  }

  @override
  Future<void> lab(LabAction action) async => calls.add(action);
}
