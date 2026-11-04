import 'wire.dart';

/// Why a job run started. Wire names equal the enum names.
enum JobTrigger { alarm, boot, watchdog, packageReplaced, timeChanged, prerequisiteLost, resumed, manual }

/// Conditions a job needs. [batteryUnrestricted] and [notBackgroundRestricted]
/// are enforced for every job on every Android version, requested or not.
enum Prereq { location, backgroundLocation, batteryUnrestricted, notBackgroundRestricted }

/// How a job's next alarm is armed.
enum JobMode { exact, inexact, stopped }

/// Pages [Dozeless.openSettings] can open.
enum Setting { batteryOptimization, appDetails, exactAlarm, autostart, forceStopGuard }

List<Prereq> _prereqs(Object? raw) => [
      for (final name in (raw as List?) ?? const [])
        ?Prereq.values.asNameMap()[name],
    ];

class JobStatus {
  const JobStatus({
    required this.id,
    required this.mode,
    this.nextRunAt,
    this.lastRunAt,
    this.lastFinishedAt,
    this.lastDurationMs,
    this.lastError,
    this.lastTrigger,
    this.runCount = 0,
    this.skippedBusyCount = 0,
    this.missing = const [],
    this.stoppedAt,
  });

  factory JobStatus.fromMap(Map<Object?, Object?> m) => JobStatus(
        id: m['id']! as String,
        mode: enumByName(JobMode.values, m['mode'], JobMode.exact),
        nextRunAt: timeOrNull(m['nextRunAt']),
        lastRunAt: timeOrNull(m['lastRunAt']),
        lastFinishedAt: timeOrNull(m['lastFinishedAt']),
        lastDurationMs: intOrNull(m['lastDurationMs']),
        lastError: m['lastError'] as String?,
        lastTrigger: m['lastTrigger'] == null ? null : enumByName(JobTrigger.values, m['lastTrigger'], JobTrigger.alarm),
        runCount: intOrNull(m['runCount']) ?? 0,
        skippedBusyCount: intOrNull(m['skippedBusyCount']) ?? 0,
        missing: _prereqs(m['missing']),
        stoppedAt: timeOrNull(m['stoppedAt']),
      );

  final String id;
  final JobMode mode;
  final DateTime? nextRunAt;
  final DateTime? lastRunAt;
  final DateTime? lastFinishedAt;
  final int? lastDurationMs;
  final String? lastError;
  final JobTrigger? lastTrigger;
  final int runCount;
  final int skippedBusyCount;

  /// Why the job is [JobMode.stopped].
  final List<Prereq> missing;
  final DateTime? stoppedAt;
}

class PrerequisiteStatus {
  const PrerequisiteStatus({
    required this.location,
    required this.backgroundLocation,
    required this.batteryUnrestricted,
    required this.backgroundRestricted,
    required this.exactAlarm,
    required this.notification,
    this.autostartSettingAvailable = false,
    this.forceStopGuard = false,
    this.forceStopGuardAvailable = false,
  });

  factory PrerequisiteStatus.fromMap(Map<Object?, Object?> m) => PrerequisiteStatus(
        location: m['location'] == true,
        backgroundLocation: m['backgroundLocation'] == true,
        batteryUnrestricted: m['batteryUnrestricted'] == true,
        backgroundRestricted: m['backgroundRestricted'] == true,
        exactAlarm: m['exactAlarm'] == true,
        notification: m['notification'] == true,
        autostartSettingAvailable: m['autostartSettingAvailable'] == true,
        forceStopGuard: m['forceStopGuard'] == true,
        forceStopGuardAvailable: m['forceStopGuardAvailable'] == true,
      );

  /// Enforced for every job.
  static const always = {Prereq.batteryUnrestricted, Prereq.notBackgroundRestricted};

  final bool location;
  final bool backgroundLocation;
  final bool batteryUnrestricted;

  final bool backgroundRestricted;

  /// Not blocking: without it jobs run in [JobMode.inexact].
  final bool exactAlarm;

  /// Not blocking: without it the user is not told when jobs stop.
  final bool notification;

  /// This brand has an Autostart page; the wizard should ask the user to enable it.
  final bool autostartSettingAvailable;

  /// Not blocking: the force-stop guard (a device admin without policies) is active,
  /// so Settings disables this app's "Force stop" button.
  final bool forceStopGuard;

  /// The app declared `DozelessAdminReceiver`, so [Setting.forceStopGuard] can be requested.
  final bool forceStopGuardAvailable;

  bool has(Prereq p) => switch (p) {
        Prereq.location => location,
        Prereq.backgroundLocation => backgroundLocation,
        Prereq.batteryUnrestricted => batteryUnrestricted,
        Prereq.notBackgroundRestricted => !backgroundRestricted,
      };

  /// What stops a job that requires [requires], in [Prereq] order.
  List<Prereq> missingFor(Set<Prereq> requires) {
    final need = {...requires, ...always};
    return [for (final p in Prereq.values) if (need.contains(p) && !has(p)) p];
  }
}

class DeviceState {
  const DeviceState({
    this.deviceId,
    this.deviceIdle = false,
    this.interactive = false,
    this.powerSaveMode = false,
    this.standbyBucket = 'unknown',
    this.autoTime = true,
    this.timezone = '',
    this.cellLevel,
    this.wifiLevel,
  });

  factory DeviceState.fromMap(Map<Object?, Object?> m) => DeviceState(
        deviceId: m['deviceId'] as String?,
        deviceIdle: m['deviceIdle'] == true,
        interactive: m['interactive'] == true,
        powerSaveMode: m['powerSaveMode'] == true,
        standbyBucket: (m['standbyBucket'] as String?) ?? 'unknown',
        autoTime: m['autoTime'] != false,
        timezone: (m['timezone'] as String?) ?? '',
        cellLevel: intOrNull(m['cellLevel']),
        wifiLevel: intOrNull(m['wifiLevel']),
      );

  /// ANDROID_ID.
  final String? deviceId;
  final bool deviceIdle;
  final bool interactive;
  final bool powerSaveMode;

  /// exempted · active · workingSet · frequent · rare · restricted · never · unknown
  final String standbyBucket;
  final bool autoTime;
  final String timezone;

  /// Signal level 0–4, null when unknown.
  final int? cellLevel;
  final int? wifiLevel;
}

class BootInfo {
  const BootInfo({this.bootCount, required this.bootTime, required this.firstJobSinceBoot});

  factory BootInfo.fromMap(Map<Object?, Object?> m) => BootInfo(
        bootCount: intOrNull(m['bootCount']),
        bootTime: timeOrNull(m['bootTime']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        firstJobSinceBoot: m['firstJobSinceBoot'] == true,
      );

  final int? bootCount;
  final DateTime bootTime;
  final bool firstJobSinceBoot;
}

/// Something the plugin saw outside a job run.
///
/// | type              | data                                                                 |
/// |-------------------|----------------------------------------------------------------------|
/// | `boot`            | bootCount, bootTime, shutdownAt, shutdownSource (marker·lastJob·unknown), viaBroadcast |
/// | `timeChanged`     | jumpMs (null if unknown), autoTime                                   |
/// | `timezoneChanged` | from, to                                                             |
/// | `processExit`     | reason (e.g. USER_REQUESTED), reasonCode, importance, description    |
class SystemEvent {
  const SystemEvent({required this.seq, required this.type, required this.at, this.data = const {}});

  factory SystemEvent.fromMap(Map<Object?, Object?> m) => SystemEvent(
        seq: intOrNull(m['seq'])!,
        type: m['type']! as String,
        at: timeOrNull(m['at'])!,
        data: {for (final e in asMap(m['data']).entries) e.key! as String: e.value},
      );

  final int seq;
  final String type;
  final DateTime at;
  final Map<String, Object?> data;
}

/// Text of the ordinary notification shown when jobs stop for a missing prerequisite.
class StopNotification {
  const StopNotification({
    this.title = 'Background work stopped',
    this.body = 'Open the app to fix its permissions or battery settings.',
    this.channelName = 'Background status',
  });

  final String title;
  final String body;
  final String channelName;

  Map<String, String> toMap() => {
        'notificationTitle': title,
        'notificationBody': body,
        'notificationChannel': channelName,
      };
}
