import 'package:dozeless/dozeless.dart';

import '../spike_jobs.dart';
import '../spike_row.dart';

/// A job the example schedules, as the screens describe it.
class JobInfo {
  const JobInfo({required this.id, required this.every, required this.summary, this.requires = const {}});

  final String id;
  final Duration every;
  final String summary;

  /// The `requires` it is scheduled with in `spike_jobs.dart`. [PrerequisiteStatus.always] applies on top.
  final Set<Prereq> requires;
}

const spikeJobInfo = JobInfo(
  id: spikeJobId,
  every: spikeInterval,
  summary: 'Takes a location fix on every run.',
  requires: {Prereq.location, Prereq.backgroundLocation},
);
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

typedef ScheduledJob = ({JobInfo job, JobStatus status});

/// The jobs taken together, and what would stop them.
class JobsSummary {
  JobsSummary(List<JobInfo> jobs, Map<String, JobStatus> statuses, this.prerequisites)
      : all = jobs,
        scheduled = [
          for (final job in jobs)
            if (statuses[job.id] case final status?) (job: job, status: status),
        ];

  final List<JobInfo> all;
  final List<ScheduledJob> scheduled;
  final PrerequisiteStatus prerequisites;

  bool get anyScheduled => scheduled.isNotEmpty;

  /// Stopped for a missing prerequisite; they resume when the app comes back with it fixed.
  List<ScheduledJob> get stopped => [for (final s in scheduled) if (s.status.mode == JobMode.stopped) s];

  /// Scheduled and not stopped.
  List<ScheduledJob> get active => [for (final s in scheduled) if (s.status.mode != JobMode.stopped) s];

  bool get allStopped => anyScheduled && active.isEmpty;

  /// Active jobs that miss a prerequisite right now. dozeless stops them at their next run, because
  /// `schedule()` doesn't check prerequisites.
  List<JobInfo> get stopping => [
        for (final s in active)
          if (prerequisites.missingFor(s.job.requires).isNotEmpty) s.job,
      ];

  /// What [jobs] need that is missing now, in [Prereq] order.
  List<Prereq> missingFor(Iterable<JobInfo> jobs) => prerequisites.missingFor({for (final j in jobs) ...j.requires});

  /// Missing prerequisites of the stopped jobs, as they recorded them.
  List<Prereq> get stoppedFor =>
      {for (final s in stopped) ...s.status.missing}.toList()..sort((a, b) => a.index - b.index);

  /// The active job that runs first.
  ({JobInfo job, DateTime at})? get next {
    ({JobInfo job, DateTime at})? soonest;
    for (final s in active) {
      final at = s.status.nextRunAt;
      if (at != null && (soonest == null || at.isBefore(soonest.at))) soonest = (job: s.job, at: at);
    }
    return soonest;
  }

  int get runCount => scheduled.fold(0, (n, s) => n + s.status.runCount);

  DateTime? get lastRunAt => scheduled
      .map((s) => s.status.lastRunAt)
      .fold<DateTime?>(null, (latest, t) => t != null && (latest == null || t.isAfter(latest)) ? t : latest);

  JobStatus? get withError => scheduled.map((s) => s.status).where((s) => s.lastError != null).firstOrNull;

  /// exact, inexact or stopped when every scheduled job agrees, otherwise mixed.
  String get mode {
    final modes = {for (final s in scheduled) s.status.mode};
    return modes.length == 1 ? modes.single.name : 'mixed';
  }
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

/// How a [SetupAction] went.
enum FixResult {
  /// A dialog or settings page opened.
  opened,

  /// This phone has no such page.
  noPage,

  /// The permission is permanently denied, so Android won't show its dialog again.
  wontAsk,
}

/// Debug actions in the Lab.
enum LabAction { runNow, fireIn10s, simulateLostAlarm, clearRows, disableForceStopGuard }

/// The platform side of the app. The screens never call plugins directly, so tests can swap this.
abstract interface class ExampleBackend {
  Future<Snapshot> load();

  Future<void> startJobs();

  Future<void> stopJobs();

  Future<FixResult> fix(SetupAction action);

  Future<void> lab(LabAction action);
}
