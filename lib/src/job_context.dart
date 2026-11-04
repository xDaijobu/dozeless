import 'models.dart';
import 'wire.dart';

/// A job body. Must be a top-level or static function annotated with
/// `@pragma('vm:entry-point')`; it runs in a background FlutterEngine.
typedef JobCallback = Future<void> Function(JobContext ctx);

/// Everything the plugin knows about one run.
class JobContext {
  const JobContext({
    required this.jobId,
    required this.trigger,
    required this.scheduledAt,
    required this.firedAt,
    required this.delayMs,
    required this.timeout,
    required this.mode,
    required this.boot,
    required this.systemEvents,
    required this.prerequisites,
    required this.device,
    this.lastRunAt,
    this.lastError,
    this.stoppedAt,
  });

  factory JobContext.fromMap(Map<Object?, Object?> m) => JobContext(
        jobId: m['jobId']! as String,
        trigger: enumByName(JobTrigger.values, m['trigger'], JobTrigger.alarm),
        scheduledAt: timeOrNull(m['scheduledAt'])!,
        firedAt: timeOrNull(m['firedAt'])!,
        delayMs: intOrNull(m['delayMs']) ?? 0,
        timeout: Duration(milliseconds: intOrNull(m['timeoutMs']) ?? 45000),
        mode: enumByName(JobMode.values, m['mode'], JobMode.exact),
        boot: BootInfo.fromMap(asMap(m['boot'])),
        systemEvents: [
          for (final e in (m['systemEvents'] as List?) ?? const []) SystemEvent.fromMap(asMap(e)),
        ],
        prerequisites: PrerequisiteStatus.fromMap(asMap(m['prerequisites'])),
        device: DeviceState.fromMap(asMap(m['device'])),
        lastRunAt: timeOrNull(m['lastRunAt']),
        lastError: m['lastError'] as String?,
        stoppedAt: timeOrNull(m['stoppedAt']),
      );

  final String jobId;
  final JobTrigger trigger;
  final DateTime scheduledAt;
  final DateTime firedAt;

  /// How late the alarm fired.
  final int delayMs;
  final Duration timeout;
  final JobMode mode;
  final BootInfo boot;

  /// Events since this job's last successful run. Delivered again if this run fails.
  final List<SystemEvent> systemEvents;
  final PrerequisiteStatus prerequisites;
  final DeviceState device;

  /// Start of the previous run, for gap detection.
  final DateTime? lastRunAt;
  final String? lastError;

  /// When the job was stopped; set on [JobTrigger.resumed] runs.
  final DateTime? stoppedAt;

  /// The plugin stops waiting at this moment; keep every step inside it.
  DateTime get deadline => firedAt.add(timeout);
}
