import 'package:flutter/material.dart';

import '../spike_row.dart';
import 'common.dart';
import 'format.dart';
import 'theme.dart';

/// One job run on the timeline: when, which job and trigger, how late, how long, where, and the device state.
class RunTile extends StatelessWidget {
  const RunTile({super.key, required this.row, required this.interval});

  /// A run this late misses the screen-off test's bar for the median delay.
  static const lateMs = 10000;

  final SpikeRow row;

  /// The job's interval. A fix older than two of them is stale, the same bar as "fresh fix" in the Lab.
  final Duration interval;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = StatusColors.of(context);
    final r = row;
    final fixAge = r.fixAgeMs == null ? null : span(r.fixAgeMs!);
    final stale = r.fixAgeMs != null && r.fixAgeMs! >= 2 * interval.inMilliseconds;
    final late = r.delayMs >= lateMs;
    final accuracy = r.accuracyM == null ? '' : ', ±${r.accuracyM!.round()} m';
    final (IconData locIcon, String locText, Color locColor) = switch (r.locationStatus) {
      'OK' when stale => (Icons.location_on_outlined, 'stale fix, $fixAge old$accuracy', status.warn),
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

    final timeStyle = theme.textTheme.titleSmall?.copyWith(fontFeatures: tabularFigures);

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: _timeWidth(context, timeStyle) + 8,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(clockMs(r.firedAt), style: timeStyle, maxLines: 1, softWrap: false),
          ),
        ),
        // The dot shows the worst of the run: no location, then late or stale, then fine.
        _Rail(color: late && locColor != scheme.error ? status.warn : locColor, line: scheme.outlineVariant),
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
                _Fact(
                  late ? Icons.running_with_errors : Icons.alarm,
                  r.delayMs < 0 ? '${span(-r.delayMs)} early' : '${span(r.delayMs)} late',
                  color: late ? status.warn : null,
                ),
                _Fact(Icons.timer_outlined, 'took ${span(r.finishedAt - r.startedAt)}'),
                _Fact(locIcon, locText, iconColor: locColor, color: stale ? status.warn : null),
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

/// Width of the widest time, "00:00:00" in tabular figures, at the user's text size.
double _timeWidth(BuildContext context, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: '00:00:00', style: DefaultTextStyle.of(context).style.merge(style)),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
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
  const _Fact(this.icon, this.text, {this.iconColor, this.color});

  final IconData icon;
  final String text;
  final Color? iconColor;

  /// Icon and text color for a fact that needs attention.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color ?? iconColor ?? muted),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(color: color ?? muted, fontFeatures: tabularFigures),
        ),
      ),
    ]);
  }
}
