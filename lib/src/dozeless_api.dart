import 'dart:async';
import 'dart:ui' show PluginUtilities;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'dispatcher.dart';
import 'job_context.dart';
import 'models.dart';

/// AlarmManager-only job runner (spec §3).
class Dozeless {
  Dozeless._();

  @visibleForTesting
  static const MethodChannel channel = MethodChannel('dozeless');

  /// Turns a callback into its raw handle; tests replace it.
  @visibleForTesting
  static int? Function(Function callback) callbackHandleOf =
      (callback) => PluginUtilities.getCallbackHandle(callback)?.toRawHandle();

  static const Duration minInterval = Duration(minutes: 1);

  /// Alarm broadcasts are killed after 60 s, and engine start-up eats into that.
  static const Duration maxTimeout = Duration(seconds: 50);

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_.-]{1,64}$');
  static AppLifecycleListener? _lifecycle;

  /// Call once in `main()` after `WidgetsFlutterBinding.ensureInitialized()`.
  /// Stores the dispatcher, repairs alarms lost to a force stop or an unseen
  /// reboot, and re-checks prerequisites every time the app is resumed.
  static Future<void> initialize({StopNotification stopNotification = const StopNotification()}) async {
    final handle = callbackHandleOf(dozelessDispatcher);
    if (handle == null) throw StateError('dozeless: dispatcher handle unavailable');
    await channel.invokeMethod<void>('initialize', {'dispatcherHandle': handle, ...stopNotification.toMap()});
    _lifecycle ??= AppLifecycleListener(onResume: () => unawaited(channel.invokeMethod<void>('reconcile')));
  }

  /// Creates or updates job [id]. Safe to call on every app start: an armed
  /// job keeps its next run unless [every], [timeout] or [requires] changed.
  static Future<void> schedule({
    required String id,
    required JobCallback callback,
    required Duration every,
    Set<Prereq> requires = const {},
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (!_idPattern.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'use 1-64 of A-Z a-z 0-9 _ . -');
    }
    if (every < minInterval) throw ArgumentError.value(every, 'every', 'must be at least 1 minute');
    if (timeout <= Duration.zero || timeout > maxTimeout) {
      throw ArgumentError.value(timeout, 'timeout', 'must be within (0, 50 s]');
    }
    final handle = callbackHandleOf(callback);
    if (handle == null) {
      throw ArgumentError.value(callback, 'callback',
          "must be a top-level or static function annotated with @pragma('vm:entry-point')");
    }
    await channel.invokeMethod<void>('schedule', {
      'id': id,
      'callbackHandle': handle,
      'everyMs': every.inMilliseconds,
      'timeoutMs': timeout.inMilliseconds,
      'requires': requires.map((p) => p.name).toList()..sort(),
    });
  }

  static Future<void> cancel(String id) => channel.invokeMethod<void>('cancel', {'id': id});

  static Future<JobStatus?> status(String id) async {
    final map = await channel.invokeMapMethod<Object?, Object?>('status', {'id': id});
    return map == null ? null : JobStatus.fromMap(map);
  }

  /// Runs [id] now with trigger=manual. Does not move the alarm chain.
  static Future<void> runNow(String id) => channel.invokeMethod<void>('runNow', {'id': id});

  static Future<PrerequisiteStatus> checkPrerequisites() async =>
      PrerequisiteStatus.fromMap((await channel.invokeMapMethod<Object?, Object?>('checkPrerequisites'))!);

  /// Returns false when this device has no such page.
  static Future<bool> openSettings(Setting setting) async =>
      (await channel.invokeMethod<bool>('openSettings', {'setting': setting.name})) ?? false;

  /// Debug: move [id]'s next alarm to [delay] from now.
  static Future<void> debugFireIn(String id, Duration delay) =>
      channel.invokeMethod<void>('debugFireIn', {'id': id, 'delayMs': delay.inMilliseconds});

  /// Debug: cancel [id]'s alarm and mark it 3 intervals late, as if the OEM dropped it.
  static Future<void> debugSimulateLostAlarm(String id) =>
      channel.invokeMethod<void>('debugSimulateLostAlarm', {'id': id});

  /// Debug: run the hourly watchdog check now.
  static Future<void> debugRunWatchdog() => channel.invokeMethod<void>('debugRunWatchdog');
}
