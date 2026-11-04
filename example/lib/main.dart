import 'package:dozeless/dozeless.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'spike_db.dart';
import 'spike_jobs.dart';
import 'ui/app.dart';
import 'ui/model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Dozeless.initialize(
    stopNotification: const StopNotification(
      title: 'Background jobs stopped',
      body: 'Open Dozeless Example to fix the permission or battery setting.',
      channelName: 'Job status',
    ),
  );
  runApp(const DozelessExampleApp(backend: PluginBackend()));
}

/// The real [ExampleBackend]: dozeless, permission_handler and spike.db.
class PluginBackend implements ExampleBackend {
  const PluginBackend();

  @override
  Future<Snapshot> load() async {
    final prerequisites = await Dozeless.checkPrerequisites();
    final statuses = {
      for (final job in exampleJobs) job.id: ?await Dozeless.status(job.id),
    };
    final rows = await SpikeDb.since(DateTime.now().subtract(const Duration(hours: 24)));
    return Snapshot(prerequisites: prerequisites, statuses: statuses, rows: rows);
  }

  @override
  Future<void> startJobs() => startSpike();

  @override
  Future<void> stopJobs() => stopSpike();

  @override
  Future<bool> fix(SetupAction action) => switch (action) {
        SetupAction.location => _request(Permission.location),
        SetupAction.backgroundLocation => _request(Permission.locationAlways),
        SetupAction.notification => _request(Permission.notification),
        SetupAction.batteryOptimization => Dozeless.openSettings(Setting.batteryOptimization),
        SetupAction.appDetails => Dozeless.openSettings(Setting.appDetails),
        SetupAction.exactAlarm => Dozeless.openSettings(Setting.exactAlarm),
        SetupAction.autostart => Dozeless.openSettings(Setting.autostart),
        SetupAction.forceStopGuard => Dozeless.openSettings(Setting.forceStopGuard),
      };

  /// False when Android no longer shows the dialog, so the user has to go to app info.
  static Future<bool> _request(Permission permission) async => !(await permission.request()).isPermanentlyDenied;

  @override
  Future<void> lab(LabAction action) async {
    switch (action) {
      case LabAction.runNow:
        await Dozeless.runNow(spikeJobId);
      case LabAction.fireIn10s:
        await Dozeless.debugFireIn(spikeJobId, const Duration(seconds: 10));
      case LabAction.simulateLostAlarm:
        await Dozeless.debugSimulateLostAlarm(spikeJobId);
        await Dozeless.debugRunWatchdog();
      case LabAction.clearRows:
        await SpikeDb.clear();
      case LabAction.disableForceStopGuard:
        await Dozeless.disableForceStopGuard();
    }
  }
}
