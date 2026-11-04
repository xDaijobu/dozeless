import 'dart:async';

import 'package:dozeless/dozeless.dart';
import 'package:dozeless_example/ui/app.dart';
import 'package:dozeless_example/ui/model.dart';
import 'package:dozeless_example/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  Snapshot snapshot({
    Map<String, JobStatus> statuses = const {},
    List rows = const [],
    bool location = true,
    bool batteryUnrestricted = true,
    bool forceStopGuard = false,
  }) =>
      Snapshot(
        prerequisites: prereqs(
          location: location,
          batteryUnrestricted: batteryUnrestricted,
          forceStopGuardAvailable: true,
          forceStopGuard: forceStopGuard,
        ),
        statuses: statuses,
        rows: [...rows],
      );

  // Built inside each test, so the countdown doesn't depend on when the file loaded.
  JobStatus status(String id, {JobMode mode = JobMode.exact, Duration nextIn = const Duration(seconds: 42)}) =>
      JobStatus(
        id: id,
        mode: mode,
        nextRunAt: mode == JobMode.stopped ? null : DateTime.now().add(nextIn),
        lastRunAt: DateTime.now().subtract(const Duration(seconds: 18)),
        lastDurationMs: 2100,
        lastTrigger: JobTrigger.alarm,
        runCount: 128,
        missing: mode == JobMode.stopped ? const [Prereq.batteryUnrestricted] : const [],
      );

  Map<String, JobStatus> running() =>
      {'spike': status('spike'), 'slow': status('slow', nextIn: const Duration(minutes: 4))};

  Map<String, JobStatus> stopped() =>
      {'spike': status('spike', mode: JobMode.stopped), 'slow': status('slow', mode: JobMode.stopped)};

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

  // Each action shows a snack bar; drop it so it never covers the next tap.
  Future<void> tapTile(WidgetTester tester, String title) async {
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).removeCurrentSnackBar();
    await tester.scrollUntilVisible(find.text(title), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text(title));
    await tester.pump();
  }

  /// One spike alarm run per minute, from [from] minutes ago down to [to], 30 s past each minute.
  List spikeRuns(int from, {int to = 0, int every = 1}) =>
      [for (var m = to; m <= from; m += every) runRow(ago: Duration(minutes: m, seconds: 30))];

  testWidgets('Overview: not started, Start jobs schedules them', (tester) async {
    final backend = await pumpApp(tester, snapshot());

    expect(find.text('Dozeless Example'), findsOneWidget);
    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('Not scheduled.'), findsNWidgets(2));
    await tester.tap(find.widgetWithText(FilledButton, 'Start jobs'));
    await tester.pump();
    expect(backend.calls, ['start']);
    expect(find.text('Started spike and slow'), findsOneWidget);
  });

  testWidgets('Overview: running jobs show a countdown and Stop jobs', (tester) async {
    final backend = await pumpApp(tester, snapshot(statuses: running()));

    expect(find.text('Running'), findsOneWidget);
    expect(find.text('spike next'), findsOneWidget);
    // The exact value is checked with a fixed clock in overview_test.dart.
    expect(find.textContaining(RegExp(r'^\d:\d\d$')), findsOneWidget);
    expect(find.text('256'), findsOneWidget);

    await tester.ensureVisible(find.text('Stop jobs'));
    await tester.pump();
    await tester.tap(find.text('Stop jobs'));
    await tester.pump();
    expect(backend.calls, ['stop']);
  });

  testWidgets('Overview: a stopped job says what is missing', (tester) async {
    await pumpApp(tester, snapshot(batteryUnrestricted: false, statuses: stopped()));

    expect(find.text('Stopped'), findsOneWidget);
    expect(find.textContaining('Missing unrestricted battery.'), findsOneWidget);
  });

  testWidgets('Overview: Open Setup scrolls to the checklist', (tester) async {
    await pumpApp(tester, snapshot(batteryUnrestricted: false, statuses: stopped()));
    expect(find.text('Battery not optimized').hitTestable(), findsNothing);

    await tester.tap(find.text('Open Setup'));
    await tester.pump();
    // The scroll starts after the next frame and takes 300 ms.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Setup').hitTestable(), findsOneWidget);
    expect(find.text('Battery not optimized').hitTestable(), findsOneWidget);
  });

  testWidgets('Overview: a missing settings page offers app info', (tester) async {
    final backend = await pumpApp(tester, snapshot(batteryUnrestricted: false));
    backend.fixResult = FixResult.noPage;

    final fix = find.widgetWithText(FilledButton, 'Fix').first;
    await tester.ensureVisible(fix);
    await tester.pump();
    await tester.tap(fix);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(backend.calls, [SetupAction.batteryOptimization]);
    expect(find.text('This phone has no battery optimization page. Change it in app info.'), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, 'App info'));
    await tester.pump();
    expect(backend.calls, [SetupAction.batteryOptimization, SetupAction.appDetails]);
  });

  testWidgets('Overview: a permanently denied permission says Android won’t ask again', (tester) async {
    final backend = await pumpApp(tester, snapshot(location: false));
    backend.fixResult = FixResult.wontAsk;

    final fix = find.widgetWithText(FilledButton, 'Fix').first;
    await tester.ensureVisible(fix);
    await tester.pump();
    await tester.tap(fix);
    await tester.pump();
    expect(backend.calls, [SetupAction.location]);
    expect(find.text('Android won’t ask for location again. Change it in app info.'), findsOneWidget);
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

  testWidgets('Runs: waiting for the first run while the jobs are running', (tester) async {
    await pumpApp(tester, snapshot(statuses: running()));
    await openTab(tester, 'Runs');

    expect(find.text('Waiting for the first run'), findsOneWidget);
    expect(
      find.text('A run shows up here for the spike job every minute and the slow job every 5 minutes, '
          'also while the screen is off.'),
      findsOneWidget,
    );
    expect(find.text('For a run right away, use Run now in the Lab.'), findsOneWidget);
    expect(find.text('Start jobs'), findsNothing);
  });

  testWidgets('Runs: with spike stopped and slow running, no spike run is promised', (tester) async {
    await pumpApp(
      tester,
      snapshot(location: false, statuses: {
        'spike': status('spike', mode: JobMode.stopped),
        'slow': status('slow', nextIn: const Duration(minutes: 4)),
      }),
    );
    await openTab(tester, 'Runs');

    expect(find.text('Waiting for the first run'), findsOneWidget);
    expect(
      find.text('A run shows up here for the slow job every 5 minutes, also while the screen is off. '
          'spike is stopped: fix Setup first.'),
      findsOneWidget,
    );
    expect(find.textContaining('Run now'), findsNothing);
    expect(find.text('Open Setup'), findsOneWidget);
  });

  testWidgets('Runs: with every job stopped, Open Setup goes to the checklist', (tester) async {
    await pumpApp(tester, snapshot(batteryUnrestricted: false, statuses: stopped()));
    await openTab(tester, 'Runs');

    expect(find.text('The jobs are stopped'), findsOneWidget);
    await tester.tap(find.text('Open Setup'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Dozeless Example'), findsOneWidget);
    expect(find.text('Setup').hitTestable(), findsOneWidget);
  });

  testWidgets('Lab: every debug action while the jobs run', (tester) async {
    final backend = await pumpApp(
      tester,
      snapshot(statuses: running(), forceStopGuard: true, rows: spikeRuns(31)),
    );
    await openTab(tester, 'Lab');

    await tapTile(tester, 'Run now');
    expect(find.text('Asked spike to run. It starts once no other run is busy.'), findsOneWidget);
    await tapTile(tester, 'Alarm in 10 s');
    await tapTile(tester, 'Simulate lost alarm');
    await tapTile(tester, 'Turn off force-stop guard');
    await tapTile(tester, 'Clear rows');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Clear all rows?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear rows'));
    await tester.pump();
    await tapTile(tester, 'Battery optimization');
    await tapTile(tester, 'Exact alarms');
    await tapTile(tester, 'App info');

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

  for (final (name, statuses, hint) in [
    ('not scheduled', <String, JobStatus>{}, 'Start the jobs first.'),
    ('stopped', null, 'Spike is stopped: fix Setup first.'),
  ]) {
    testWidgets('Lab: the spike actions wait while spike is $name', (tester) async {
      final backend = await pumpApp(tester, snapshot(batteryUnrestricted: false, statuses: statuses ?? stopped()));
      await openTab(tester, 'Lab');

      for (final title in ['Run now', 'Alarm in 10 s', 'Simulate lost alarm']) {
        final tile = find.widgetWithText(ListTile, title);
        expect(tester.widget<ListTile>(tile).enabled, isFalse, reason: title);
        expect(find.descendant(of: tile, matching: find.textContaining(hint)), findsOneWidget, reason: title);
      }
      await tester.tap(find.text('Run now'));
      await tester.pump();
      expect(backend.calls, isEmpty);
    });
  }

  testWidgets('Lab: NOT YET until the runs cover the window, then PASS', (tester) async {
    await pumpApp(tester, snapshot(statuses: running(), rows: spikeRuns(31)));
    await openTab(tester, 'Lab');

    expect(find.text('NOT YET'), findsOneWidget);
    expect(find.text('31 of 90 min collected'), findsOneWidget);

    await tester.tap(find.text('30 min'));
    await tester.pump();
    expect(find.text('PASS'), findsOneWidget);
    expect(find.textContaining('min collected'), findsNothing);
  });

  testWidgets('Lab: a covered window with too few runs is FAIL', (tester) async {
    await pumpApp(tester, snapshot(statuses: running(), rows: spikeRuns(31, every: 2)));
    await openTab(tester, 'Lab');
    await tester.tap(find.text('30 min'));
    await tester.pump();

    expect(find.text('FAIL'), findsOneWidget);
    final context = tester.element(find.text('Screen-off test'));
    expect(tester.widget<Text>(find.textContaining('(50.0%)')).style?.color, Theme.of(context).colorScheme.error);
  });

  testWidgets('Lab: rows before the first spike alarm run don’t count', (tester) async {
    await pumpApp(
      tester,
      snapshot(statuses: running(), rows: [
        ...spikeRuns(4),
        // An hour-old stop and a slow run: neither starts the window.
        runRow(ago: const Duration(minutes: 60), trigger: 'prerequisiteLost'),
        runRow(ago: const Duration(minutes: 70), jobId: 'slow', locationStatus: 'SLOW'),
      ]),
    );
    await openTab(tester, 'Lab');

    expect(find.text('NOT YET'), findsOneWidget);
    expect(find.text('4 of 90 min collected'), findsOneWidget);
  });

  testWidgets('Lab: with no runs the criteria stay neutral', (tester) async {
    await pumpApp(tester, snapshot());
    await openTab(tester, 'Lab');

    final context = tester.element(find.text('Screen-off test'));
    final pass = StatusColors.of(context).good;
    final fail = Theme.of(context).colorScheme.error;
    Color? colorOf(String text) => tester.widget<Text>(find.text(text)).style?.color;

    expect(find.text('NOT YET'), findsOneWidget);
    expect(find.text('0 of 90 min collected'), findsOneWidget);
    expect(find.text('spike isn’t running, so no new runs come in.'), findsOneWidget);
    expect(find.text('–'), findsOneWidget, reason: 'median delay');
    for (final value in ['–', '0 (0.0%)']) {
      expect(colorOf(value), isNot(anyOf(pass, fail)), reason: value);
    }
    for (final zero in tester.widgetList<Text>(find.text('0'))) {
      expect(zero.style?.color, isNot(anyOf(pass, fail)));
    }
  });

  testWidgets('Shell: a failed first load shows the error and Try again', (tester) async {
    usePhoneScreen(tester);
    final backend = FakeBackend(snapshot())..loadError = Exception('channel down');
    await tester.pumpWidget(DozelessExampleApp(backend: backend));
    await tester.pump();

    expect(find.text('Couldn’t read the job status'), findsOneWidget);
    expect(find.text('Exception: channel down'), findsOneWidget);

    backend.loadError = null;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.text('Not started'), findsOneWidget);
  });

  testWidgets('Shell: a load that finishes after a newer one started is dropped', (tester) async {
    usePhoneScreen(tester);
    final backend = _ManualBackend(snapshot());
    await tester.pumpWidget(DozelessExampleApp(backend: backend));
    await tester.tap(find.byTooltip('Refresh'));
    expect(backend.loads, hasLength(2));

    backend.loads[1].complete(snapshot(statuses: running()));
    await tester.pump();
    expect(find.text('Running'), findsOneWidget);

    backend.loads[0].complete(snapshot());
    await tester.pump();
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Not started'), findsNothing);
  });
}

/// Every [load] waits until the test completes it.
class _ManualBackend extends FakeBackend {
  _ManualBackend(super.snapshot);

  final loads = <Completer<Snapshot>>[];

  @override
  Future<Snapshot> load() {
    final load = Completer<Snapshot>();
    loads.add(load);
    return load.future;
  }
}
