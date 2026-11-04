import 'dart:math' as math;

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
    required this.onShowSetup,
    this.setupKey,
  });

  final Snapshot snapshot;
  final Future<void> Function() onRefresh;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final ValueChanged<SetupAction> onFix;
  final VoidCallback onShowSetup;

  /// On the Setup header, so [onShowSetup] can scroll to it.
  final Key? setupKey;

  @override
  Widget build(BuildContext context) {
    final p = snapshot.prerequisites;
    final items = setupItemsFor(p);
    return Refreshable(onRefresh: onRefresh, children: [
      StatusHero(
        jobs: exampleJobs,
        statuses: snapshot.statuses,
        prerequisites: p,
        onStart: onStart,
        onStop: onStop,
        onShowSetup: onShowSetup,
      ),
      const SectionHeader('Jobs'),
      for (final job in exampleJobs) ...[
        JobCard(job: job, status: snapshot.statuses[job.id], missingNow: p.missingFor(job.requires)),
        const SizedBox(height: 12),
      ],
      SectionHeader(
        'Setup',
        key: setupKey,
        trailing: Text(setupProgress(items), style: Theme.of(context).textTheme.labelLarge),
      ),
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

/// location, location all the time and unrestricted battery
String _prereqs(Iterable<Prereq> missing) {
  final labels = missing.map(_prereqLabel).toList();
  if (labels.length < 2) return labels.join();
  return '${labels.sublist(0, labels.length - 1).join(', ')} and ${labels.last}';
}

/// spike, or spike and slow.
String _names(Iterable<JobInfo> jobs) => jobs.map((j) => j.id).join(' and ');

/// The first thing on screen: are the jobs running, will they keep running, and when is the next run.
class StatusHero extends StatelessWidget {
  const StatusHero({
    super.key,
    required this.jobs,
    required this.statuses,
    required this.prerequisites,
    required this.onStart,
    required this.onStop,
    required this.onShowSetup,
    this.now = DateTime.now,
  });

  final List<JobInfo> jobs;
  final Map<String, JobStatus> statuses;
  final PrerequisiteStatus prerequisites;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onShowSetup;

  /// The countdown's clock; tests pass a fixed one.
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = StatusColors.of(context);
    final s = JobsSummary(jobs, statuses, prerequisites);
    final stopped = [for (final e in s.stopped) e.job];
    final stopping = s.stopping;
    final needed = s.missingFor(jobs);

    final (Color bg, Color fg, String headline, String detail, bool toSetup) = switch (s) {
      _ when !s.anyScheduled && needed.isEmpty => (
          scheme.surfaceContainerHigh,
          scheme.onSurface,
          'Not started',
          'Start the jobs, then see on the Runs tab when each run fired, also with the screen off.',
          false,
        ),
      _ when !s.anyScheduled => (
          scheme.surfaceContainerHigh,
          scheme.onSurface,
          'Not started',
          'Fix Setup first: without ${_prereqs(needed)}, the jobs stop at their first run.',
          true,
        ),
      _ when s.allStopped => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          'Stopped',
          'Missing ${_prereqs(s.stoppedFor)}. Fix it in Setup and come back to the app: '
              'the jobs resume on their own.',
          true,
        ),
      _ when stopped.isNotEmpty => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          'Partly stopped',
          '${_names(stopped)} stopped: missing ${_prereqs(s.stoppedFor)}. '
              '${_names([for (final e in s.active) e.job])} keeps running. Fix it in Setup and come back to the app.',
          true,
        ),
      _ when stopping.isNotEmpty => (
          status.warnContainer,
          status.onWarnContainer,
          'Setup needed',
          '${stopping.length == s.active.length ? 'The jobs stop' : '${_names(stopping)} stops'} at the next run: '
              'missing ${_prereqs(s.missingFor(stopping))}. Fix it in Setup.',
          true,
        ),
      _ when s.active.any((e) => e.status.mode == JobMode.inexact) => (
          status.warnContainer,
          status.onWarnContainer,
          'Running',
          'Inexact alarms: Android may move each run by minutes. Allow exact alarms in Setup.',
          true,
        ),
      _ => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
          'Running',
          'Exact alarms, allowed while idle. The Runs tab shows how late each run fired.',
          false,
        ),
    };
    final error = s.withError;
    final lastRun = s.lastRunAt;
    final next = s.next;

    return Card(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _NextRunRing(job: next?.job, at: next?.at, color: fg, now: now),
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
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Figure(label: 'Runs', value: count(s.runCount), color: fg),
              const SizedBox(width: 12),
              _Figure(label: 'Last run', value: lastRun == null ? '–' : clock(lastRun), color: fg),
              const SizedBox(width: 12),
              _Figure(label: 'Mode', value: s.mode, color: fg),
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
          if (toSetup) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onShowSetup,
              style: TextButton.styleFrom(foregroundColor: fg, minimumSize: const Size.fromHeight(40)),
              icon: const Icon(Icons.checklist),
              label: const Text('Open Setup'),
            ),
          ],
        ]),
      ),
    );
  }
}

/// A dial that fills up over the job's interval, with the time left in the middle.
class _NextRunRing extends StatelessWidget {
  const _NextRunRing({required this.job, required this.at, required this.color, required this.now});

  static const size = 112.0;
  static const stroke = 8.0;

  /// The largest square inside the ring, so the text never touches it, whatever the font size.
  static final inner = (size / 2 - stroke) * math.sqrt2;

  final JobInfo? job;
  final DateTime? at;
  final Color color;
  final DateTime Function() now;

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
      clock: now,
      builder: (context, left) => SizedBox.square(
        dimension: size,
        child: Stack(alignment: Alignment.center, children: [
          _ring(1 - (left.inMilliseconds / job.every.inMilliseconds).clamp(0.0, 1.0)),
          SizedBox.square(
            dimension: inner,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  countdown(left),
                  style: text.headlineMedium
                      ?.copyWith(color: color, fontWeight: FontWeight.w600, fontFeatures: tabularFigures),
                ),
                Text('${job.id} next', style: text.labelSmall?.copyWith(color: color)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _ring(double value) => SizedBox.square(
        dimension: size,
        child: CircularProgressIndicator(
          value: value,
          strokeWidth: stroke,
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
        // Shrinks instead of running into the next figure at large font sizes.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: text.titleLarge?.copyWith(color: color, fontFeatures: tabularFigures)),
        ),
        Text(label, style: text.labelMedium?.copyWith(color: color.withValues(alpha: 0.8))),
      ]),
    );
  }
}

/// One scheduled job: what it does and how its alarm chain is doing.
class JobCard extends StatelessWidget {
  const JobCard({
    super.key,
    required this.job,
    required this.status,
    this.missingNow = const [],
    this.now = DateTime.now,
  });

  final JobInfo job;
  final JobStatus? status;

  /// Prerequisites the job lacks right now. An active job stops at its next run without them.
  final List<Prereq> missingNow;

  /// The countdown's clock; tests pass a fixed one.
  final DateTime Function() now;

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
              Text('Stopped: missing ${_prereqs(s.missing)}.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ] else if (s.mode != JobMode.stopped && missingNow.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Stops at its next run: missing ${_prereqs(missingNow)}.',
                  style: theme.textTheme.bodySmall?.copyWith(color: StatusColors.of(context).warn)),
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
      clock: now,
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
