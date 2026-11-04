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
    required this.now,
    required this.onRefresh,
    required this.onAction,
    required this.onOpen,
  });

  /// Newest first.
  final List<SpikeRow> rows;
  final PrerequisiteStatus prerequisites;
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
    final now = widget.now;
    final rows = widget.rows;
    final oldest = rows.isEmpty ? now : DateTime.fromMillisecondsSinceEpoch(rows.last.firedAt);
    final windowStart = now.subtract(_window);
    final from = oldest.isAfter(windowStart) ? oldest : windowStart;
    final stats = SpikeStats.compute(rows, jobId: spikeJobId, interval: spikeInterval, from: from, to: now);
    final p = widget.prerequisites;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Refreshable(onRefresh: widget.onRefresh, children: [
      ScreenOffTestCard(
        stats: stats,
        window: _window,
        from: from,
        onWindowChanged: (w) => setState(() => _window = w),
      ),
      const SectionHeader('Debug actions'),
      Card(
        child: Column(children: [
          _ActionTile(
            icon: Icons.play_circle_outline,
            title: 'Run now',
            subtitle: 'Runs spike once with trigger manual. Its alarm chain stays as it is.',
            onTap: () => widget.onAction(LabAction.runNow),
          ),
          _ActionTile(
            icon: Icons.alarm_add_outlined,
            title: 'Alarm in 10 s',
            subtitle: 'Moves the next spike alarm to 10 seconds from now.',
            onTap: () => widget.onAction(LabAction.fireIn10s),
          ),
          _ActionTile(
            icon: Icons.alarm_off_outlined,
            title: 'Simulate lost alarm',
            subtitle: 'Cancels the spike alarm as if the phone dropped it, then runs the watchdog that repairs it.',
            onTap: () => widget.onAction(LabAction.simulateLostAlarm),
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
        child: Text('Undo a fix here to watch dozeless stop the jobs, then resume them when you come back.', style: muted),
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

/// Pass/fail numbers of the "screen off for 90 minutes" test.
class ScreenOffTestCard extends StatelessWidget {
  const ScreenOffTestCard({
    super.key,
    required this.stats,
    required this.window,
    required this.from,
    required this.onWindowChanged,
  });

  static const windows = [Duration(minutes: 30), Duration(minutes: 90)];

  final SpikeStats stats;
  final Duration window;

  /// Where counting starts: the window start, or the oldest row when that is later.
  final DateTime from;
  final ValueChanged<Duration> onWindowChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = StatusColors.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    Color verdict(bool ok) => ok ? status.good : scheme.error;
    final s = stats;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Screen-off test', style: theme.textTheme.titleMedium)),
            Pill(
              label: s.passes ? 'PASS' : 'NOT YET',
              icon: s.passes ? Icons.check : Icons.hourglass_empty,
              background: s.passes ? status.goodContainer : scheme.surfaceContainerHighest,
              foreground: s.passes ? status.onGoodContainer : scheme.onSurfaceVariant,
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            'Start the jobs, turn the screen off and leave the phone alone. '
            'This counts the alarm runs of the spike job.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final w in windows)
              ChoiceChip(
                label: Text('${w.inMinutes} min'),
                selected: window == w,
                onSelected: (_) => onWindowChanged(w),
              ),
          ]),
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
              metric('median delay', span(s.medianDelayMs), color: verdict(s.medianDelayMs < 10000)),
              metric('located', count(s.withLocation), color: verdict(s.withLocation == s.ran)),
              metric('fresh fix', count(s.withFreshLocation)),
            ]);
          }),
          const SizedBox(height: 16),
          Text(
            'Passes with at least 95% of the expected runs, a median delay under 10 s and a location on every run. '
            'Counting from ${clock(from)}.',
            style: muted,
          ),
        ]),
      ),
    );
  }
}
