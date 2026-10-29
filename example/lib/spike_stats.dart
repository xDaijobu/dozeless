import 'spike_row.dart';

/// Pass/fail numbers for the "screen off 90 minutes" test (spec §9).
class SpikeStats {
  const SpikeStats({
    required this.expected,
    required this.ran,
    required this.medianDelayMs,
    required this.withLocation,
    required this.withFreshLocation,
  });

  /// Alarm runs of [jobId] fired in [from, to).
  factory SpikeStats.compute(
    List<SpikeRow> rows, {
    required String jobId,
    required Duration interval,
    required DateTime from,
    required DateTime to,
  }) {
    final runs = rows
        .where((r) =>
            r.jobId == jobId &&
            r.trigger == 'alarm' &&
            r.firedAt >= from.millisecondsSinceEpoch &&
            r.firedAt < to.millisecondsSinceEpoch)
        .toList();
    final delays = runs.map((r) => r.delayMs).toList()..sort();
    final mid = delays.length ~/ 2;
    final median = delays.isEmpty
        ? 0
        : delays.length.isOdd
            ? delays[mid]
            : (delays[mid - 1] + delays[mid]) ~/ 2;
    return SpikeStats(
      expected: to.difference(from).inMilliseconds ~/ interval.inMilliseconds,
      ran: runs.length,
      medianDelayMs: median,
      withLocation: runs.where((r) => r.lat != null).length,
      withFreshLocation:
          runs.where((r) => r.fixAgeMs != null && r.fixAgeMs! < 2 * interval.inMilliseconds).length,
    );
  }

  final int expected;
  final int ran;
  final int medianDelayMs;
  final int withLocation;

  /// Rows whose fix is younger than two intervals. Background apps may get cached positions.
  final int withFreshLocation;

  double get ranRatio => expected == 0 ? 0 : ran / expected;

  /// ≥ 95% of runs, median delay < 10 s, every row has a location.
  bool get passes => ranRatio >= 0.95 && medianDelayMs < 10000 && withLocation == ran;
}
