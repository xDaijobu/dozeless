import 'package:flutter/material.dart';

import '../spike_row.dart';
import 'common.dart';
import 'format.dart';
import 'theme.dart';

/// One job run on the timeline: when, which job and trigger, how late, how long, where, and the device state.
class RunTile extends StatelessWidget {
  const RunTile({super.key, required this.row});

  final SpikeRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = StatusColors.of(context);
    final r = row;
    final fixAge = r.fixAgeMs == null ? null : span(r.fixAgeMs!);
    final accuracy = r.accuracyM == null ? '' : ', ±${r.accuracyM!.round()} m';
    final (IconData locIcon, String locText, Color locColor) = switch (r.locationStatus) {
      'OK' => (Icons.location_on_outlined, fixAge == null ? 'location OK' : 'fix $fixAge old$accuracy', status.good),
      'LAST_KNOWN' => (Icons.history, 'last known fix${fixAge == null ? '' : ', $fixAge old'}$accuracy', status.warn),
      'FAILED' => (Icons.location_off_outlined, 'no location', scheme.error),
      'SLOW' => (Icons.location_disabled_outlined, 'no location needed', scheme.secondary),
      final other => (Icons.location_searching, other, scheme.onSurfaceVariant),
    };
    final (Color triggerBg, Color triggerFg) = switch (r.trigger) {
      'alarm' => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      'manual' => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      _ => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    };

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 68,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(clockMs(r.firedAt), style: theme.textTheme.titleSmall?.copyWith(fontFeatures: tabularFigures)),
          ),
        ),
        _Rail(color: locColor, line: scheme.outlineVariant),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 0, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(r.jobId, style: theme.textTheme.titleSmall),
                Pill(label: r.trigger, background: triggerBg, foreground: triggerFg),
                if (r.deviceIdle)
                  Pill(
                    label: 'Doze',
                    icon: Icons.bedtime,
                    background: scheme.inverseSurface,
                    foreground: scheme.onInverseSurface,
                  ),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 14, runSpacing: 4, children: [
                _Fact(Icons.alarm, r.delayMs < 0 ? '${span(-r.delayMs)} early' : '${span(r.delayMs)} late'),
                _Fact(Icons.timer_outlined, 'took ${span(r.finishedAt - r.startedAt)}'),
                _Fact(locIcon, locText, iconColor: locColor),
                _Fact(Icons.signal_cellular_alt, 'bucket ${r.standbyBucket}'),
                if (r.events.isNotEmpty) _Fact(Icons.bolt, r.events.split(',').join(', ')),
              ]),
              if (r.error != null) ...[
                const SizedBox(height: 4),
                Text(
                  r.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}

/// The timeline's vertical line with a dot in the run's location color.
class _Rail extends StatelessWidget {
  const _Rail({required this.color, required this.line});

  final Color color;
  final Color line;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 16,
        child: Stack(alignment: Alignment.topCenter, children: [
          Positioned.fill(child: Center(child: SizedBox(width: 2, height: double.infinity, child: ColoredBox(color: line)))),
          Padding(
            padding: const EdgeInsets.only(top: 15),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
              ),
              child: const SizedBox.square(dimension: 12),
            ),
          ),
        ]),
      );
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text, {this.iconColor});

  final IconData icon;
  final String text;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: iconColor ?? muted),
      const SizedBox(width: 4),
      Flexible(
        child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: muted, fontFeatures: tabularFigures)),
      ),
    ]);
  }
}
