/// One job run recorded by the feasibility app. Times are epoch milliseconds.
class SpikeRow {
  const SpikeRow({
    this.id,
    required this.jobId,
    required this.trigger,
    required this.scheduledAt,
    required this.firedAt,
    required this.delayMs,
    required this.startedAt,
    required this.finishedAt,
    this.lat,
    this.lon,
    this.accuracyM,
    this.fixAgeMs,
    required this.locationStatus,
    required this.deviceIdle,
    required this.interactive,
    required this.standbyBucket,
    required this.mode,
    required this.batteryUnrestricted,
    this.events = '',
    this.error,
  });

  factory SpikeRow.fromMap(Map<String, Object?> m) => SpikeRow(
        id: m['id'] as int?,
        jobId: m['jobId']! as String,
        trigger: m['trigger']! as String,
        scheduledAt: m['scheduledAt']! as int,
        firedAt: m['firedAt']! as int,
        delayMs: m['delayMs']! as int,
        startedAt: m['startedAt']! as int,
        finishedAt: m['finishedAt']! as int,
        lat: m['lat'] as double?,
        lon: m['lon'] as double?,
        accuracyM: m['accuracyM'] as double?,
        fixAgeMs: m['fixAgeMs'] as int?,
        locationStatus: m['locationStatus']! as String,
        deviceIdle: m['deviceIdle'] == 1,
        interactive: m['interactive'] == 1,
        standbyBucket: m['standbyBucket']! as String,
        mode: m['mode']! as String,
        batteryUnrestricted: m['batteryUnrestricted'] == 1,
        events: (m['events'] as String?) ?? '',
        error: m['error'] as String?,
      );

  final int? id;
  final String jobId;
  final String trigger;
  final int scheduledAt;
  final int firedAt;
  final int delayMs;
  final int startedAt;
  final int finishedAt;
  final double? lat;
  final double? lon;
  final double? accuracyM;

  /// How old the fix was when the job read it; large values mean a cached position.
  final int? fixAgeMs;

  /// OK · LAST_KNOWN · FAILED · SLOW
  final String locationStatus;
  final bool deviceIdle;
  final bool interactive;
  final String standbyBucket;
  final String mode;
  final bool batteryUnrestricted;

  /// Comma-separated `ctx.systemEvents` types.
  final String events;
  final String? error;

  Map<String, Object?> toMap() => {
        'jobId': jobId,
        'trigger': trigger,
        'scheduledAt': scheduledAt,
        'firedAt': firedAt,
        'delayMs': delayMs,
        'startedAt': startedAt,
        'finishedAt': finishedAt,
        'lat': lat,
        'lon': lon,
        'accuracyM': accuracyM,
        'fixAgeMs': fixAgeMs,
        'locationStatus': locationStatus,
        'deviceIdle': deviceIdle ? 1 : 0,
        'interactive': interactive ? 1 : 0,
        'standbyBucket': standbyBucket,
        'mode': mode,
        'batteryUnrestricted': batteryUnrestricted ? 1 : 0,
        'events': events,
        'error': error,
      };
}
