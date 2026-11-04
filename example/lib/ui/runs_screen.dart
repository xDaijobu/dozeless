import 'package:flutter/material.dart';

import '../spike_row.dart';
import 'common.dart';
import 'format.dart';
import 'model.dart';
import 'run_tile.dart';
import 'theme.dart';

/// The last 24 hours of runs, newest first, grouped by day.
class RunsScreen extends StatefulWidget {
  const RunsScreen({
    super.key,
    required this.rows,
    required this.jobs,
    required this.now,
    required this.onRefresh,
    required this.onStart,
    required this.onShowSetup,
  });

  /// Newest first.
  final List<SpikeRow> rows;

  /// The empty state says what to do next from this.
  final JobsSummary jobs;
  final DateTime now;
  final Future<void> Function() onRefresh;
  final VoidCallback onStart;
  final VoidCallback onShowSetup;

  @override
  State<RunsScreen> createState() => _RunsScreenState();
}

class _RunsScreenState extends State<RunsScreen> {
  static const _all = '';
  static final _intervals = {for (final j in exampleJobs) j.id: j.every};

  String _job = _all;

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return Refreshable(onRefresh: widget.onRefresh, children: [
        RunsEmptyState(jobs: widget.jobs, onStart: widget.onStart, onShowSetup: widget.onShowSetup),
      ]);
    }
    final rows = _job == _all ? widget.rows : widget.rows.where((r) => r.jobId == _job).toList();
    final entries = <Object>[];
    String? day;
    for (final r in rows) {
      final label = dayLabel(DateTime.fromMillisecondsSinceEpoch(r.firedAt), widget.now);
      if (label != day) entries.add(day = label);
      entries.add(r);
    }
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: entries.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return _header(rows);
          return switch (entries[i - 1]) {
            final SpikeRow r => RunTile(row: r, interval: _intervals[r.jobId] ?? spikeJobInfo.every),
            final label => Padding(
                padding: const EdgeInsets.fromLTRB(4, 20, 4, 4),
                child: Text('$label', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
              ),
          };
        },
      ),
    );
  }

  Widget _header(List<SpikeRow> rows) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RunsSummary(rows: rows),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(value: _all, label: Text('All jobs')),
            for (final job in exampleJobs) ButtonSegment(value: job.id, label: Text(job.id)),
          ],
          selected: {_job},
          onSelectionChanged: (s) => setState(() => _job = s.single),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text('No $_job runs in the last 24 hours.', textAlign: TextAlign.center),
          ),
      ]);
}

/// Runs, runs in Doze and runs without a location, for the rows shown.
class RunsSummary extends StatelessWidget {
  const RunsSummary({super.key, required this.rows});

  final List<SpikeRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noLocation = rows.where((r) => r.locationStatus == 'FAILED').length;
    Widget figure(String label, int n, {Color? color}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(count(n), style: theme.textTheme.titleLarge?.copyWith(fontFeatures: tabularFigures, color: color)),
            Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          figure('runs in 24 h', rows.length),
          figure('in Doze', rows.where((r) => r.deviceIdle).length),
          figure('no location', noLocation, color: noLocation > 0 ? theme.colorScheme.error : null),
        ]),
      ),
    );
  }
}

/// Shown before the first run: says how to get one.
class RunsEmptyState extends StatelessWidget {
  const RunsEmptyState({super.key, required this.jobs, required this.onStart, required this.onShowSetup});

  final JobsSummary jobs;
  final VoidCallback onStart;
  final VoidCallback onShowSetup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final stopped = [for (final s in jobs.stopped) s.job];
    final stopping = jobs.stopping;
    // Active jobs with everything they need: the only ones whose runs can be promised.
    final keeps = [for (final s in jobs.active) if (!stopping.contains(s.job)) s.job];
    final (String title, String body, String? hint) = switch (jobs) {
      _ when !jobs.anyScheduled => (
          'No runs yet',
          'Start the jobs and every run shows up here: ${_cadence(jobs.all)}, also while the screen is off.',
          null,
        ),
      _ when jobs.allStopped => (
          'The jobs are stopped',
          'A setting they need is missing, so no runs come in. Fix it in Setup on the Overview tab: '
              'the jobs resume when you come back to the app.',
          null,
        ),
      _ => (
          keeps.isEmpty ? 'Setup needed' : 'Waiting for the first run',
          [
            if (keeps.isNotEmpty) 'A run shows up here for ${_cadence(keeps)}, also while the screen is off.',
            if (stopping.isNotEmpty)
              stopping.length == 1
                  ? '${_ids(stopping)} stops at its next run: a setting it needs is missing. Fix it in Setup.'
                  : '${_ids(stopping)} stop at their next run: a setting they need is missing. Fix it in Setup.',
            if (stopped.isNotEmpty) '${_ids(stopped)} ${stopped.length == 1 ? 'is' : 'are'} stopped: fix Setup first.',
          ].join(' '),
          // Run now on a job that misses a prerequisite only stops it.
          keeps.any((j) => j.id == spikeJobInfo.id) ? 'For a run right away, use Run now in the Lab.' : null,
        ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 72, 16, 16),
      child: Column(children: [
        DecoratedBox(
          decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, shape: BoxShape.circle),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Icon(Icons.timeline, size: 40, color: theme.colorScheme.onSecondaryContainer),
          ),
        ),
        const SizedBox(height: 24),
        Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center, style: muted),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(hint, textAlign: TextAlign.center, style: muted),
        ],
        if (!jobs.anyScheduled) ...[
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Start jobs'),
          ),
        ] else if (stopped.isNotEmpty || stopping.isNotEmpty) ...[
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: onShowSetup,
            icon: const Icon(Icons.checklist),
            label: const Text('Open Setup'),
          ),
        ],
      ]),
    );
  }

  /// the spike job every minute and the slow job every 5 minutes
  static String _cadence(List<JobInfo> jobs) => jobs.map((j) => 'the ${j.id} job ${every(j.every)}').join(' and ');

  /// spike, or spike and slow
  static String _ids(List<JobInfo> jobs) => jobs.map((j) => j.id).join(' and ');
}
