import 'package:dozeless/dozeless.dart';
import 'package:dozeless_example/ui/model.dart';
import 'package:dozeless_example/ui/overview_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  var now = DateTime(2026, 11, 4, 14, 2, 13);
  DateTime clock() => now;

  JobStatus status(String id, Duration nextIn) => JobStatus(
        id: id,
        mode: JobMode.exact,
        nextRunAt: now.add(nextIn),
        lastRunAt: now.subtract(const Duration(seconds: 18)),
        runCount: 128,
      );

  testWidgets('StatusHero counts down to the soonest run', (tester) async {
    now = DateTime(2026, 11, 4, 14, 2, 13);
    await tester.pumpWidget(themed(StatusHero(
      jobs: exampleJobs,
      statuses: {
        'spike': status('spike', const Duration(seconds: 42)),
        'slow': status('slow', const Duration(minutes: 4)),
      },
      onStart: () {},
      onStop: () {},
      now: clock,
    )));

    expect(find.text('0:42'), findsOneWidget);
    expect(find.text('spike next'), findsOneWidget);
    expect(find.text('256'), findsOneWidget);
    expect(find.text('14:01:55'), findsOneWidget);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:41'), findsOneWidget);
  });

  testWidgets('JobCard shows the next run time and the countdown', (tester) async {
    now = DateTime(2026, 11, 4, 14, 2, 13);
    await tester.pumpWidget(themed(JobCard(
      job: spikeJobInfo,
      status: status('spike', const Duration(seconds: 42)),
      now: clock,
    )));

    expect(find.text('14:02:55, in 0:42'), findsOneWidget);
    expect(find.text('every minute'), findsOneWidget);
  });
}
