import 'package:dozeless/dozeless.dart';
import 'package:flutter/material.dart';

import '../spike_jobs.dart';
import '../spike_row.dart';
import '../spike_stats.dart';
import 'common.dart';
import 'format.dart';
import 'model.dart';
import 'theme.dart';

/// The screen-off test and the debug actions behind `doc/test-results/`.
class LabScreen extends StatefulWidget {
  const LabScreen({
    super.key,
    required this.rows,
    required this.prerequisites,
    required this.spikeMode,
    required this.now,
    required this.onRefresh,
    required this.onAction,
    required this.onOpen,
  });

  /// Newest first.
  final List<SpikeRow> rows;
  final PrerequisiteStatus prerequisites;

  /// Null while spike is not scheduled. Run now, Alarm in 10 s and Simulate lost alarm need it scheduled (the
  /// plugin rejects an unknown id) and not stopped (the plugin skips the run or records another stop).
  final JobMode? spikeMode;
  final DateTime now;
  final Future<void> Function() onRefresh;
  final ValueChanged<LabAction> onAction;
  final ValueChanged<SetupAction> onOpen;

  @override
  State<LabScreen> createState() => _LabScreenState();
}

class _LabScreenState extends State<LabScreen> {
  Duration _window = const Duration(minutes: 90);

  @override
  Widget build(BuildContext context) {
    final window = ScreenOffWindow.of(widget.rows, _window, widget.now);
    final stats =
        SpikeStats.compute(widget.rows, jobId: spikeJobId, interval: spikeInterval, from: window.from, to: widget.now);
    final p = widget.prerequisites;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final blocked = switch (widget.spikeMode) {
      null => 'Start the jobs first.',
      JobMode.stopped => 'Spike is stopped: fix Setup first.',
      _ => null,
    };
    String spike(String what) => blocked == null ? what : '$what $blocked';
    VoidCallback? whenSpike(VoidCallback action) => blocked == null ? action : null;

    return Refreshable(onRefresh: widget.onRefresh, children: [
      ScreenOffTestCard(
        stats: stats,
        window: window,
        spikeRunning: blocked == null,
        onWindowChanged: (w) => setState(() => _window = w),
      ),
      const SectionHeader('Debug actions'),
      Card(
        child: Column(children: [
          _ActionTile(
            icon: Icons.play_circle_outline,
            title: 'Run now',
            subtitle: spike('Runs spike once with trigger manual, after any run already going. '
                'Its alarm chain stays as it is.'),
            onTap: whenSpike(() => widget.onAction(LabAction.runNow)),
          ),
          _ActionTile(
            icon: Icons.alarm_add_outlined,
            title: 'Alarm in 10 s',
            subtitle: spike('Moves the next spike alarm to 10 seconds from now.'),
            onTap: whenSpike(() => widget.onAction(LabAction.fireIn10s)),
          ),
          _ActionTile(
            icon: Icons.alarm_off_outlined,
            title: 'Simulate lost alarm',
            subtitle: spike('Cancels the spike alarm as if the phone dropped it, then runs the watchdog that repairs it.'),
            onTap: whenSpike(() => widget.onAction(LabAction.simulateLostAlarm)),
          ),
          _ActionTile(
            icon: Icons.delete_sweep_outlined,
            title: 'Clear rows',
            subtitle: 'Deletes every run from spike.db, including the ones the screen-off test counts.',
            onTap: () => _confirmClear(context),
          ),
          if (p.forceStopGuardAvailable)
            _ActionTile(
              icon: Icons.shield_outlined,
              title: 'Turn off force-stop guard',
              subtitle: p.forceStopGuard
                  ? 'Do this before uninstalling: Android won’t uninstall the app while the guard is on.'
                  : 'The guard is off. Turn it on from Setup on the Overview tab.',
              onTap: p.forceStopGuard ? () => widget.onAction(LabAction.disableForceStopGuard) : null,
            ),
        ]),
      ),
      const SectionHeader('Settings pages'),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          'Undo a fix here to watch dozeless stop the jobs, then resume them when you come back. '
          'Exact alarms is different: without it the jobs keep running on inexact alarms.',
          style: muted,
        ),
      ),
      Card(
        child: Column(children: [
          _ActionTile(
            icon: Icons.battery_saver_outlined,
            title: 'Battery optimization',
            onTap: () => widget.onOpen(SetupAction.batteryOptimization),
          ),
          _ActionTile(
            icon: Icons.alarm_on_outlined,
            title: 'Exact alarms',
            onTap: () => widget.onOpen(SetupAction.exactAlarm),
          ),
          _ActionTile(
            icon: Icons.settings_outlined,
            title: 'App info',
            onTap: () => widget.onOpen(SetupAction.appDetails),
          ),
          if (p.autostartSettingAvailable)
            _ActionTile(
              icon: Icons.restart_alt,
              title: 'Autostart',
              onTap: () => widget.onOpen(SetupAction.autostart),
            ),
        ]),
      ),
    ]);
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all rows?'),
        content: Text('This deletes ${plural(widget.rows.length, 'run')} from the last 24 hours and every older one.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear rows')),
        ],
      ),
    );
    if (ok ?? false) widget.onAction(LabAction.clearRows);
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title, this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: subtitle == null ? const Icon(Icons.open_in_new, size: 18) : null,
        enabled: onTap != null,
        onTap: onTap,
      );
}

/// The stretch of time the screen-off test judges.
class ScreenOffWindow {
  const ScreenOffWindow({required this.length, required this.from, required this.covered});

  /// Starts at the first `spike` alarm run in [rows] (newest first), so time before the jobs ran doesn't count
  /// against them, and at most [length] before [now].
  factory ScreenOffWindow.of(List<SpikeRow> rows, Duration length, DateTime now) {
    final first = rows.where((r) => r.jobId == spikeJobId && r.trigger == 'alarm').lastOrNull;
    if (first == null) return ScreenOffWindow(length: length, from: now, covered: Duration.zero);
    final start = now.subtract(length);
    final firstAt = DateTime.fromMillisecondsSinceEpoch(first.firedAt);
    final from = firstAt.isAfter(start) ? firstAt : start;
    return ScreenOffWindow(length: length, from: from, covered: now.difference(from));
  }

  final Duration length;
  final DateTime from;

  /// How much of [length] the runs cover so far.
  final Duration covered;

  /// The runs cover the whole window, so the numbers can pass or fail.
  bool get complete => covered >= length;
}

/// Pass/fail numbers of the "screen off for 90 minutes" test.
class ScreenOffTestCard extends StatelessWidget {
  const ScreenOffTestCard({
    super.key,
    required this.stats,
    required this.window,
    required this.onWindowChanged,
    this.spikeRunning = true,
  });

  static const windows = [Duration(minutes: 30), Duration(minutes: 90)];

  final SpikeStats stats;
  final ScreenOffWindow window;
  final ValueChanged<Duration> onWindowChanged;

  /// False while spike isn't scheduled or is stopped, so no new runs come in.
  final bool spikeRunning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = StatusColors.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final s = stats;
    final done = window.complete;
    // Until the runs cover the whole window there is nothing to judge, so the criteria stay neutral.
    Color? verdict(bool ok) => !done ? null : ok ? status.good : scheme.error;
    final (String label, IconData icon, Color bg, Color fg) = switch (done) {
      false => ('NOT YET', Icons.hourglass_empty, scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      true when s.passes => ('PASS', Icons.check, status.goodContainer, status.onGoodContainer),
      true => ('FAIL', Icons.close, scheme.errorContainer, scheme.onErrorContainer),
    };
    final minutes = window.length.inMinutes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Screen-off test', style: theme.textTheme.titleMedium)),
            Pill(label: label, icon: icon, background: bg, foreground: fg),
          ]),
          const SizedBox(height: 4),
          Text(
            'Start the jobs, turn the screen off and leave the phone alone. This counts the alarm runs of the '
            'spike job from its first one.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final w in windows)
              ChoiceChip(
                label: Text('${w.inMinutes} min'),
                selected: window.length == w,
                onSelected: (_) => onWindowChanged(w),
              ),
          ]),
          if (!done) ...[
            const SizedBox(height: 12),
            Text(
              '${window.covered.inMinutes} of $minutes min collected',
              style: theme.textTheme.labelLarge?.copyWith(fontFeatures: tabularFigures),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: window.covered.inMilliseconds / window.length.inMilliseconds,
              borderRadius: BorderRadius.circular(4),
            ),
            if (!spikeRunning) ...[
              const SizedBox(height: 6),
              Text('spike isn’t running, so no new runs come in.', style: muted),
            ],
          ],
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final width = (constraints.maxWidth - 16) / 2;
            Widget metric(String label, String value, {Color? color}) => SizedBox(
                  width: width,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(value, style: theme.textTheme.titleLarge?.copyWith(color: color, fontFeatures: tabularFigures)),
                    Text(label, style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  ]),
                );
            return Wrap(spacing: 16, runSpacing: 16, children: [
              metric('expected', count(s.expected)),
              metric('ran', '${count(s.ran)} (${(s.ranRatio * 100).toStringAsFixed(1)}%)',
                  color: verdict(s.ranRatio >= 0.95)),
              metric('median delay', s.ran == 0 ? '–' : span(s.medianDelayMs), color: verdict(s.medianDelayMs < 10000)),
              metric('located', count(s.withLocation), color: verdict(s.withLocation == s.ran)),
              metric('fresh fix', count(s.withFreshLocation)),
            ]);
          }),
          const SizedBox(height: 16),
          Text(
            'Passes with at least 95% of the expected runs, a median delay under 10 s and a location on every run, '
            'once the runs cover the whole $minutes min. Counting from ${clock(window.from)}.',
            style: muted,
          ),
        ]),
      ),
    );
  }
}
