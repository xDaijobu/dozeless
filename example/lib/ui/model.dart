import 'package:dozeless/dozeless.dart';

import '../spike_jobs.dart';
import '../spike_row.dart';

/// A job the example schedules, as the screens describe it.
class JobInfo {
  const JobInfo({required this.id, required this.every, required this.summary});

  final String id;
  final Duration every;
  final String summary;
}

const spikeJobInfo = JobInfo(id: spikeJobId, every: spikeInterval, summary: 'Takes a location fix on every run.');
const slowJobInfo = JobInfo(id: slowJobId, every: slowInterval, summary: 'Holds the wake lock for 20 s on every run.');
const exampleJobs = [spikeJobInfo, slowJobInfo];

/// Everything the screens show, read in one go.
class Snapshot {
  const Snapshot({required this.prerequisites, required this.statuses, required this.rows});

  final PrerequisiteStatus prerequisites;

  /// By job id. A job without an entry is not scheduled.
  final Map<String, JobStatus> statuses;

  /// The last 24 hours, newest first.
  final List<SpikeRow> rows;
}

/// How the jobs are doing, taken together.
enum JobsState {
  notScheduled,

  /// Every scheduled job is stopped for a missing prerequisite.
  stopped,
  running;

  factory JobsState.of(Map<String, JobStatus> statuses) => statuses.isEmpty
      ? notScheduled
      : statuses.values.every((s) => s.mode == JobMode.stopped)
          ? stopped
          : running;
}

/// What a Fix button (or a settings shortcut) does.
enum SetupAction {
  location('location'),
  backgroundLocation('location all the time'),
  notification('notifications'),
  batteryOptimization('battery optimization'),
  appDetails('app info'),
  exactAlarm('exact alarms'),
  autostart('Autostart'),
  forceStopGuard('the force-stop guard');

  const SetupAction(this.label);

  final String label;
}

/// Debug actions in the Lab.
enum LabAction { runNow, fireIn10s, simulateLostAlarm, clearRows, disableForceStopGuard }

/// The platform side of the app. The screens never call plugins directly, so tests can swap this.
abstract interface class ExampleBackend {
  Future<Snapshot> load();

  Future<void> startJobs();

  Future<void> stopJobs();

  /// False when nothing opened: the device has no such page, or Android won't ask for the permission again.
  Future<bool> fix(SetupAction action);

  Future<void> lab(LabAction action);
}
