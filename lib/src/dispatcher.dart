import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'job_context.dart';

const MethodChannel _background = MethodChannel('dozeless/background');

/// Entry point of the background engine. Registered by [Dozeless.initialize].
@pragma('vm:entry-point')
void dozelessDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  _background.setMethodCallHandler(handleBackgroundCall);
  _background.invokeMethod<void>('dispatcherReady');
}

/// Runs one job and completes only when the callback has finished.
@visibleForTesting
Future<Object?> handleBackgroundCall(
  MethodCall call, {
  Function? Function(CallbackHandle handle) resolve = PluginUtilities.getCallbackFromHandle,
}) async {
  if (call.method != 'runJob') {
    throw MissingPluginException('dozeless/background has no method ${call.method}');
  }
  final args = (call.arguments as Map).cast<Object?, Object?>();
  final raw = (args['callbackHandle']! as num).toInt();
  final callback = resolve(CallbackHandle.fromRawHandle(raw));
  if (callback is! JobCallback) {
    throw PlatformException(code: 'CALLBACK_NOT_FOUND', message: 'no JobCallback for handle $raw');
  }
  final ctx = JobContext.fromMap((args['context']! as Map).cast<Object?, Object?>());
  try {
    await callback(ctx);
  } catch (e, st) {
    throw PlatformException(code: 'JOB_FAILED', message: '$e', details: '$st');
  }
  return null;
}
