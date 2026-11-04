import 'package:dozeless/dozeless.dart';
import 'package:dozeless_example/ui/app.dart';
import 'package:dozeless_example/ui/model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  Snapshot snapshot({
    Map<String, JobStatus> statuses = const {},
    List rows = const [],
    bool batteryUnrestricted = true,
    bool forceStopGuard = false,
  }) =>
      Snapshot(
        prerequisites: prereqs(
          batteryUnrestricted: batteryUnrestricted,
          forceStopGuardAvailable: true,
          forceStopGuard: forceStopGuard,
        ),
        statuses: statuses,
        rows: [...rows],
      );

  JobStatus status(String id, {JobMode mode = JobMode.exact, Duration nextIn = const Duration(seconds: 42)}) =>
      JobStatus(
        id: id,
        mode: mode,
        nextRunAt: DateTime.now().add(nextIn),
        lastRunAt: DateTime.now().subtract(const Duration(seconds: 18)),
        lastDurationMs: 2100,
        lastTrigger: JobTrigger.alarm,
        runCount: 128,
      );

  Future<FakeBackend> pumpApp(WidgetTester tester, Snapshot s) async {
    usePhoneScreen(tester);
    final backend = FakeBackend(s);
    await tester.pumpWidget(DozelessExampleApp(backend: backend));
    await tester.pump();
    return backend;
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('Overview: not started, Start jobs schedules them', (tester) async {
    final backend = await pumpApp(tester, snapshot());

    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('Not scheduled.'), findsNWidgets(2));
    await tester.tap(find.widgetWithText(FilledButton, 'Start jobs'));
    await tester.pump();
    expect(backend.calls, ['start']);
    expect(find.text('Started spike and slow'), findsOneWidget);
  });

  testWidgets('Overview: running jobs show a live countdown and Stop jobs', (tester) async {
    final backend = await pumpApp(
      tester,
      snapshot(statuses: {'spike': status('spike'), 'slow': status('slow', nextIn: const Duration(minutes: 4))}),
    );

    expect(find.text('Running'), findsOneWidget);
    expect(find.text('spike next'), findsOneWidget);
    expect(find.text('0:42'), findsOneWidget);
    expect(find.text('256'), findsOneWidget);

    await tester.ensureVisible(find.text('Stop jobs'));
    await tester.pump();
    await tester.tap(find.text('Stop jobs'));
    await tester.pump();
    expect(backend.calls, ['stop']);
  });

  testWidgets('Overview: a stopped job says what is missing', (tester) async {
    await pumpApp(
      tester,
      snapshot(
        batteryUnrestricted: false,
        statuses: {
          'spike': const JobStatus(id: 'spike', mode: JobMode.stopped, missing: [Prereq.batteryUnrestricted]),
          'slow': const JobStatus(id: 'slow', mode: JobMode.stopped, missing: [Prereq.batteryUnrestricted]),
        },
      ),
    );

    expect(find.text('Stopped'), findsOneWidget);
    expect(find.textContaining('Missing unrestricted battery.'), findsOneWidget);
  });

  testWidgets('Overview: Fix opens the setting, and offers app info when nothing opened', (tester) async {
    final backend = await pumpApp(tester, snapshot(batteryUnrestricted: false));
    backend.fixOpens = false;

    final fix = find.widgetWithText(FilledButton, 'Fix').first;
    await tester.ensureVisible(fix);
    await tester.pump();
    await tester.tap(fix);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(backend.calls, [SetupAction.batteryOptimization]);
    expect(find.text('Nothing opened for battery optimization. Change it in app info instead.'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'App info'));
    await tester.pump();
    expect(backend.calls, [SetupAction.batteryOptimization, SetupAction.appDetails]);
  });

  testWidgets('Runs: empty state, then a timeline grouped by day with a job filter', (tester) async {
    final backend = await pumpApp(tester, snapshot());
    await openTab(tester, 'Runs');

    expect(find.text('No runs yet'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Start jobs'));
    await tester.pump();
    expect(backend.calls, ['start']);

    backend.snapshot = snapshot(rows: [
      runRow(ago: const Duration(seconds: 5), deviceIdle: true),
      runRow(ago: const Duration(minutes: 1), jobId: 'slow', locationStatus: 'SLOW'),
    ]);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('runs in 24 h'), findsOneWidget);
    expect(find.text('no location needed'), findsOneWidget);
    expect(find.text('Doze'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text('spike')));
    await tester.pump();
    expect(find.text('no location needed'), findsNothing);
    expect(find.text('Doze'), findsOneWidget);
  });

  testWidgets('Lab: screen-off statistics and every debug action', (tester) async {
    final backend = await pumpApp(
      tester,
      snapshot(
        forceStopGuard: true,
        rows: [for (var m = 0; m < 30; m++) runRow(ago: Duration(minutes: m, seconds: 30))],
      ),
    );
    await openTab(tester, 'Lab');

    expect(find.text('Screen-off test'), findsOneWidget);
    expect(find.text('PASS'), findsOneWidget);
    await tester.tap(find.text('30 min'));
    await tester.pump();
    expect(find.text('PASS'), findsOneWidget);

    // Each action shows a snack bar; drop it so it never covers the next tile.
    Future<void> tap(String title) async {
      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
      await tester.scrollUntilVisible(find.text(title), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(title));
      await tester.pump();
    }

    await tap('Run now');
    await tap('Alarm in 10 s');
    await tap('Simulate lost alarm');
    await tap('Turn off force-stop guard');
    await tap('Clear rows');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Clear all rows?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear rows'));
    await tester.pump();
    await tap('Battery optimization');
    await tap('Exact alarms');
    await tap('App info');

    expect(backend.calls, [
      LabAction.runNow,
      LabAction.fireIn10s,
      LabAction.simulateLostAlarm,
      LabAction.disableForceStopGuard,
      LabAction.clearRows,
      SetupAction.batteryOptimization,
      SetupAction.exactAlarm,
      SetupAction.appDetails,
    ]);
  });

  testWidgets('Lab: NOT YET without enough runs', (tester) async {
    await pumpApp(tester, snapshot(rows: [runRow(ago: const Duration(minutes: 89)), runRow(ago: Duration.zero)]));
    await openTab(tester, 'Lab');

    expect(find.text('NOT YET'), findsOneWidget);
  });
}
