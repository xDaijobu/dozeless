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
  Future<FixResult> fix(SetupAction action) => switch (action) {
        SetupAction.location => _request(Permission.location),
        SetupAction.backgroundLocation => _request(Permission.locationAlways),
        SetupAction.notification => _request(Permission.notification),
        SetupAction.batteryOptimization => _open(Setting.batteryOptimization),
        SetupAction.appDetails => _open(Setting.appDetails),
        SetupAction.exactAlarm => _open(Setting.exactAlarm),
        SetupAction.autostart => _open(Setting.autostart),
        SetupAction.forceStopGuard => _open(Setting.forceStopGuard),
      };

  /// Permanently denied also comes back right after the dialog that denied it for good.
  static Future<FixResult> _request(Permission permission) async =>
      (await permission.request()).isPermanentlyDenied ? FixResult.wontAsk : FixResult.opened;

  static Future<FixResult> _open(Setting setting) async =>
      await Dozeless.openSettings(setting) ? FixResult.opened : FixResult.noPage;

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
