import 'package:dozeless/dozeless.dart';
import 'package:dozeless/src/dispatcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final seen = <JobContext>[];

Future<void> recordingJob(JobContext ctx) async => seen.add(ctx);

Future<void> throwingJob(JobContext ctx) async => throw StateError('boom');

MethodCall runJob() => const MethodCall('runJob', {
      'jobId': 'get',
      'callbackHandle': 1,
      'context': {'jobId': 'get', 'trigger': 'alarm', 'scheduledAt': 1, 'firedAt': 2},
    });

void main() {
  setUp(seen.clear);

  test('resolves the handle and passes the parsed context to the callback', () async {
    await handleBackgroundCall(runJob(), resolve: (_) => recordingJob);
    expect(seen.single.jobId, 'get');
    expect(seen.single.trigger, JobTrigger.alarm);
  });

  test('completes only after a slow callback has finished', () async {
    var finished = false;
    Future<void> slowJob(JobContext ctx) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      finished = true;
    }

    await handleBackgroundCall(runJob(), resolve: (_) => slowJob);
    expect(finished, isTrue);
  });

  test('a throwing job becomes a JOB_FAILED platform error', () async {
    await expectLater(
      handleBackgroundCall(runJob(), resolve: (_) => throwingJob),
      throwsA(isA<PlatformException>()
          .having((e) => e.code, 'code', 'JOB_FAILED')
          .having((e) => e.message, 'message', contains('boom'))),
    );
  });

  test('an unknown handle becomes CALLBACK_NOT_FOUND', () async {
    await expectLater(
      handleBackgroundCall(runJob(), resolve: (_) => null),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'CALLBACK_NOT_FOUND')),
    );
  });

  test('a function with the wrong signature becomes CALLBACK_NOT_FOUND', () async {
    await expectLater(
      handleBackgroundCall(runJob(), resolve: (_) => () {}),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'CALLBACK_NOT_FOUND')),
    );
  });
}
