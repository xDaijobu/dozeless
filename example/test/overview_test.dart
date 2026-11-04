import 'package:dozeless/dozeless.dart';
import 'package:dozeless_example/ui/model.dart';
import 'package:dozeless_example/ui/overview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  var now = DateTime(2026, 11, 4, 14, 2, 13);
  DateTime clock() => now;
  setUp(() => now = DateTime(2026, 11, 4, 14, 2, 13));

  JobStatus status(String id, {Duration nextIn = const Duration(seconds: 42), JobMode mode = JobMode.exact}) =>
      JobStatus(
        id: id,
        mode: mode,
        nextRunAt: mode == JobMode.stopped ? null : now.add(nextIn),
        lastRunAt: now.subtract(const Duration(seconds: 18)),
        runCount: 128,
        missing: mode == JobMode.stopped ? const [Prereq.location] : const [],
      );

  Map<String, JobStatus> both({JobMode spike = JobMode.exact, JobMode slow = JobMode.exact}) => {
        'spike': status('spike', mode: spike),
        'slow': status('slow', nextIn: const Duration(minutes: 4), mode: slow),
      };

  Widget hero(Map<String, JobStatus> statuses, {PrerequisiteStatus? prerequisites, VoidCallback? onShowSetup}) =>
      themed(StatusHero(
        jobs: exampleJobs,
        statuses: statuses,
        prerequisites: prerequisites ?? prereqs(),
        onStart: () {},
        onStop: () {},
        onShowSetup: onShowSetup ?? () {},
        now: clock,
      ));

  testWidgets('StatusHero counts down to the soonest run', (tester) async {
    await tester.pumpWidget(hero(both()));

    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Exact alarms, allowed while idle. The Runs tab shows how late each run fired.'), findsOneWidget);
    expect(find.text('0:42'), findsOneWidget);
    expect(find.text('spike next'), findsOneWidget);
    expect(find.text('256'), findsOneWidget);
    expect(find.text('14:01:55'), findsOneWidget);
    expect(find.text('exact'), findsOneWidget);
    expect(find.text('Open Setup'), findsNothing);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:41'), findsOneWidget);
  });

  testWidgets('StatusHero before Start asks for Setup when needed items are missing', (tester) async {
    await tester.pumpWidget(hero(const {}, prerequisites: prereqs(location: false, backgroundLocation: false)));

    expect(find.text('Not started'), findsOneWidget);
    expect(
      find.text('Fix Setup first: without location and location all the time, the jobs stop at their first run.'),
      findsOneWidget,
    );
    expect(find.text('Start jobs'), findsOneWidget);
    expect(find.text('Open Setup'), findsOneWidget);
  });

  testWidgets('StatusHero after Start with missing setup warns instead of looking healthy', (tester) async {
    var shown = 0;
    await tester.pumpWidget(hero(
      both(spike: JobMode.inexact, slow: JobMode.inexact),
      prerequisites: prereqs(location: false, backgroundLocation: false),
      onShowSetup: () => shown++,
    ));

    expect(find.text('Running'), findsNothing);
    expect(find.text('Setup needed'), findsOneWidget);
    expect(
      find.text('spike stops at the next run: missing location and location all the time. Fix it in Setup.'),
      findsOneWidget,
    );

    await tester.pumpWidget(hero(
      both(spike: JobMode.inexact, slow: JobMode.inexact),
      prerequisites: prereqs(location: false, backgroundLocation: false, batteryUnrestricted: false),
      onShowSetup: () => shown++,
    ));
    expect(
      find.text('The jobs stop at the next run: missing location, location all the time and unrestricted battery. '
          'Fix it in Setup.'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Open Setup'));
    await tester.pump();
    await tester.tap(find.text('Open Setup'));
    expect(shown, 1);
  });

  testWidgets('StatusHero shows a partly stopped pair as mixed, not stopped', (tester) async {
    await tester.pumpWidget(hero(
      both(spike: JobMode.stopped, slow: JobMode.inexact),
      prerequisites: prereqs(location: false),
    ));

    expect(find.text('Partly stopped'), findsOneWidget);
    expect(find.textContaining('spike stopped: missing location. slow keeps running.'), findsOneWidget);
    expect(find.text('mixed'), findsOneWidget);
    expect(find.text('stopped'), findsNothing);
  });

  testWidgets('StatusHero at font scale 2.0 keeps the figures apart and the countdown inside the ring',
      (tester) async {
    usePhoneScreen(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(hero(both()));

    final ring = tester.getRect(find.byType(CircularProgressIndicator));
    final inside = ring.width / 2 - 8; // radius minus the stroke
    for (final text in ['0:42', 'spike next']) {
      final rect = tester.getRect(find.text(text));
      for (final corner in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
        expect((corner - ring.center).distance, lessThanOrEqualTo(inside + 0.5), reason: '$text at $corner');
      }
    }

    final runs = tester.getRect(find.text('256'));
    final lastRun = tester.getRect(find.text('14:01:55'));
    final mode = tester.getRect(find.text('exact'));
    expect(lastRun.left - runs.right, greaterThanOrEqualTo(12));
    expect(mode.left - lastRun.right, greaterThanOrEqualTo(12));
  });

  testWidgets('JobCard shows the next run time and the countdown', (tester) async {
    await tester.pumpWidget(themed(JobCard(job: spikeJobInfo, status: status('spike'), now: clock)));

    expect(find.text('14:02:55, in 0:42'), findsOneWidget);
    expect(find.text('every minute'), findsOneWidget);
  });

  testWidgets('JobCard says an active job stops at its next run when setup is missing', (tester) async {
    await tester.pumpWidget(themed(JobCard(
      job: spikeJobInfo,
      status: status('spike', mode: JobMode.inexact),
      missingNow: const [Prereq.location],
      now: clock,
    )));

    expect(find.text('Stops at its next run: missing location.'), findsOneWidget);
  });
}
