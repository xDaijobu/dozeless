import 'package:dozeless/dozeless.dart';
import 'package:flutter/material.dart';

import 'common.dart';
import 'countdown.dart';
import 'format.dart';
import 'model.dart';
import 'setup_checklist.dart';
import 'theme.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({
    super.key,
    required this.snapshot,
    required this.onRefresh,
    required this.onStart,
    required this.onStop,
    required this.onFix,
  });

  final Snapshot snapshot;
  final Future<void> Function() onRefresh;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final ValueChanged<SetupAction> onFix;

  @override
  Widget build(BuildContext context) {
    final items = setupItemsFor(snapshot.prerequisites);
    return Refreshable(onRefresh: onRefresh, children: [
      StatusHero(jobs: exampleJobs, statuses: snapshot.statuses, onStart: onStart, onStop: onStop),
      const SectionHeader('Jobs'),
      for (final job in exampleJobs) ...[
        JobCard(job: job, status: snapshot.statuses[job.id]),
        const SizedBox(height: 12),
      ],
      SectionHeader('Setup', trailing: Text(setupProgress(items), style: Theme.of(context).textTheme.labelLarge)),
      SetupChecklist(items: items, onFix: onFix),
    ]);
  }
}

String _prereqLabel(Prereq p) => switch (p) {
      Prereq.location => 'location',
      Prereq.backgroundLocation => 'location all the time',
      Prereq.batteryUnrestricted => 'unrestricted battery',
      Prereq.notBackgroundRestricted => 'background usage',
    };

/// The jobs taken together.
class JobsSummary {
  factory JobsSummary(List<JobInfo> jobs, Map<String, JobStatus> statuses) {
    JobInfo? nextJob;
    DateTime? nextRunAt;
    for (final job in jobs) {
      final next = statuses[job.id]?.nextRunAt;
      if (statuses[job.id]?.mode == JobMode.stopped || next == null) continue;
      if (nextRunAt == null || next.isBefore(nextRunAt)) (nextJob, nextRunAt) = (job, next);
    }
    return JobsSummary._([for (final j in jobs) ?statuses[j.id]], nextJob, nextRunAt);
  }

  const JobsSummary._(this.scheduled, this.nextJob, this.nextRunAt);

  final List<JobStatus> scheduled;

  /// The job that runs first, among those not stopped.
  final JobInfo? nextJob;
  final DateTime? nextRunAt;

  bool get anyScheduled => scheduled.isNotEmpty;
  int get stoppedCount => scheduled.where((s) => s.mode == JobMode.stopped).length;
  bool get anyInexact => scheduled.any((s) => s.mode == JobMode.inexact);
  int get runCount => scheduled.fold(0, (n, s) => n + s.runCount);
  List<Prereq> get missing => {for (final s in scheduled) ...s.missing}.toList()..sort((a, b) => a.index - b.index);

  DateTime? get lastRunAt => scheduled
      .map((s) => s.lastRunAt)
      .fold<DateTime?>(null, (latest, t) => t != null && (latest == null || t.isAfter(latest)) ? t : latest);

  JobStatus? get withError => scheduled.where((s) => s.lastError != null).firstOrNull;
}

/// The first thing on screen: are the jobs running, and when is the next run.
class StatusHero extends StatelessWidget {
  const StatusHero({
    super.key,
    required this.jobs,
    required this.statuses,
    required this.onStart,
    required this.onStop,
  });

  final List<JobInfo> jobs;
  final Map<String, JobStatus> statuses;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = StatusColors.of(context);
    final s = JobsSummary(jobs, statuses);
    final stopped = s.stoppedCount;

    final (Color bg, Color fg, String headline, String detail) = switch (s) {
      _ when !s.anyScheduled => (
          scheme.surfaceContainerHigh,
          scheme.onSurface,
          'Not started',
          'Start the jobs and dozeless runs them on schedule, also with the screen off and the phone in Doze.',
        ),
      _ when stopped > 0 => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          stopped == s.scheduled.length ? 'Stopped' : 'Partly stopped',
          'Missing ${s.missing.map(_prereqLabel).join(', ')}. Fix it below and come back to the app: '
              'the jobs resume on their own.',
        ),
      _ when s.anyInexact => (
          status.warnContainer,
          status.onWarnContainer,
          'Running',
          'Inexact alarms: Android may move each run by minutes. Allow exact alarms below.',
        ),
      _ => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          'Running',
          'Exact alarms: each run lands on time, also in Doze.',
        ),
    };
    final error = s.withError;
    final lastRun = s.lastRunAt;

    return Card(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _NextRunRing(job: s.nextJob, at: s.nextRunAt, color: fg),
            const SizedBox(width: 20),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(headline, style: theme.textTheme.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(detail, style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
              ]),
            ),
          ]),
          if (s.anyScheduled) ...[
            const SizedBox(height: 20),
            Row(children: [
              _Figure(label: 'Runs', value: count(s.runCount), color: fg),
              _Figure(label: 'Last run', value: lastRun == null ? '–' : clock(lastRun), color: fg),
              _Figure(label: 'Mode', value: stopped > 0 ? 'stopped' : s.anyInexact ? 'inexact' : 'exact', color: fg),
            ]),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline, size: 18, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Last error in ${error.id}: ${error.lastError}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurface),
                    ),
                  ),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (s.anyScheduled)
            OutlinedButton.icon(
              onPressed: onStop,
              style: OutlinedButton.styleFrom(
                foregroundColor: fg,
                side: BorderSide(color: fg.withValues(alpha: 0.5)),
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.stop_rounded),
              label: const Text('Stop jobs'),
            )
          else
            FilledButton.icon(
              onPressed: onStart,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start jobs'),
            ),
        ]),
      ),
    );
  }
}

/// A dial that fills up over the job's interval, with the time left in the middle.
class _NextRunRing extends StatelessWidget {
  const _NextRunRing({required this.job, required this.at, required this.color});

  static const size = 112.0;

  final JobInfo? job;
  final DateTime? at;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final job = this.job, at = this.at;
    if (job == null || at == null) {
      return SizedBox.square(
        dimension: size,
        child: Stack(alignment: Alignment.center, children: [
          _ring(0),
          Icon(Icons.bedtime_outlined, size: 40, color: color),
        ]),
      );
    }
    final text = Theme.of(context).textTheme;
    return Countdown(
      target: at,
      builder: (context, left) => SizedBox.square(
        dimension: size,
        child: Stack(alignment: Alignment.center, children: [
          _ring(1 - (left.inMilliseconds / job.every.inMilliseconds).clamp(0.0, 1.0)),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              countdown(left),
              style: text.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.w600, fontFeatures: tabularFigures),
            ),
            Text('${job.id} next', style: text.labelSmall?.copyWith(color: color)),
          ]),
        ]),
      ),
    );
  }

  Widget _ring(double value) => SizedBox.square(
        dimension: size,
        child: CircularProgressIndicator(
          value: value,
          strokeWidth: 8,
          strokeCap: StrokeCap.round,
          color: color,
          backgroundColor: color.withValues(alpha: 0.15),
        ),
      );
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: text.titleLarge?.copyWith(color: color, fontFeatures: tabularFigures)),
        Text(label, style: text.labelMedium?.copyWith(color: color.withValues(alpha: 0.8))),
      ]),
    );
  }
}

/// One scheduled job: what it does and how its alarm chain is doing.
class JobCard extends StatelessWidget {
  const JobCard({super.key, required this.job, required this.status});

  final JobInfo job;
  final JobStatus? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final s = status;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(job.id, style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            Expanded(child: Text(every(job.every), style: muted)),
            ModePill(mode: s?.mode),
          ]),
          const SizedBox(height: 4),
          Text(job.summary, style: theme.textTheme.bodyMedium),
          if (s == null) ...[
            const SizedBox(height: 8),
            Text('Not scheduled.', style: muted),
          ] else ...[
            const SizedBox(height: 12),
            _FactGrid(facts: [
              ('Next run', _nextRun(s)),
              ('Runs', Text(count(s.runCount), style: _value(theme))),
              ('Last run', Text(_lastRun(s), style: _value(theme))),
              ('Skipped while busy', Text(count(s.skippedBusyCount), style: _value(theme))),
            ]),
            if (s.missing.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Stopped: missing ${s.missing.map(_prereqLabel).join(', ')}.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ],
            if (s.lastError != null) ...[
              const SizedBox(height: 8),
              Text('Last error: ${s.lastError}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ],
          ],
        ]),
      ),
    );
  }

  static TextStyle? _value(ThemeData theme) => theme.textTheme.bodyLarge?.copyWith(fontFeatures: tabularFigures);

  Widget _nextRun(JobStatus s) {
    final at = s.nextRunAt;
    if (at == null || s.mode == JobMode.stopped) return Builder(builder: (c) => Text('–', style: _value(Theme.of(c))));
    return Countdown(
      target: at,
      builder: (c, left) => Text(
        left <= Duration.zero ? '${clock(at)}, due' : '${clock(at)}, in ${countdown(left)}',
        style: _value(Theme.of(c)),
      ),
    );
  }

  static String _lastRun(JobStatus s) {
    final at = s.lastRunAt;
    if (at == null) return '–';
    final parts = [clock(at), ?s.lastTrigger?.name, if (s.lastDurationMs != null) span(s.lastDurationMs!)];
    return parts.join(', ');
  }
}

class ModePill extends StatelessWidget {
  const ModePill({super.key, required this.mode});

  final JobMode? mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = StatusColors.of(context);
    final (bg, fg) = switch (mode) {
      JobMode.exact => (status.goodContainer, status.onGoodContainer),
      JobMode.inexact => (status.warnContainer, status.onWarnContainer),
      JobMode.stopped => (scheme.errorContainer, scheme.onErrorContainer),
      null => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Pill(label: mode?.name ?? 'not scheduled', background: bg, foreground: fg);
  }
}

/// Label-over-value pairs in two columns.
class _FactGrid extends StatelessWidget {
  const _FactGrid({required this.facts});

  final List<(String, Widget)> facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 16.0;
      final width = (constraints.maxWidth - gap) / 2;
      return Wrap(spacing: gap, runSpacing: 12, children: [
        for (final (name, value) in facts)
          SizedBox(
            width: width,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: label), value]),
          ),
      ]);
    });
  }
}
