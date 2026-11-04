import 'package:dozeless_example/spike_row.dart';
import 'package:dozeless_example/ui/format.dart';
import 'package:dozeless_example/ui/run_tile.dart';
import 'package:dozeless_example/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final firedAt = DateTime(2026, 11, 4, 14, 2, 13);

  Widget tile(SpikeRow row) => themed(RunTile(row: row, interval: const Duration(minutes: 1)));

  testWidgets('shows time, job, trigger, delay, duration, fix, bucket and events', (tester) async {
    await tester.pumpWidget(tile(
      runRow(firedAt: firedAt, delayMs: 1200, durationMs: 2100, fixAgeMs: 3000, events: 'boot,processExit'),
    ));

    expect(find.text('14:02:13'), findsOneWidget);
    expect(find.text('spike'), findsOneWidget);
    expect(find.text('alarm'), findsOneWidget);
    expect(find.text('1.2 s late'), findsOneWidget);
    expect(find.text('took 2.1 s'), findsOneWidget);
    expect(find.text('fix 3.0 s old, ±12 m'), findsOneWidget);
    expect(find.text('bucket active'), findsOneWidget);
    expect(find.text('boot, processExit'), findsOneWidget);
    expect(find.text('Doze'), findsNothing);
  });

  testWidgets('keeps the time on one line with a larger system font', (tester) async {
    usePhoneScreen(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(tile(runRow(firedAt: firedAt)));
    expect(MediaQuery.textScalerOf(tester.element(find.byType(RunTile))).scale(10), closeTo(13, 0.01));

    final time = tester.renderObject<RenderParagraph>(find.text('14:02:13'));
    expect(time.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(time.size.width));
    expect(time.didExceedMaxLines, isFalse);
  });

  testWidgets('marks runs in Doze', (tester) async {
    await tester.pumpWidget(tile(runRow(firedAt: firedAt, deviceIdle: true)));

    expect(find.text('Doze'), findsOneWidget);
    expect(find.byIcon(Icons.bedtime), findsOneWidget);
  });

  testWidgets('describes each location status', (tester) async {
    Future<void> show(String status, {int? fixAgeMs}) =>
        tester.pumpWidget(tile(runRow(firedAt: firedAt, locationStatus: status, fixAgeMs: fixAgeMs, accuracyM: null)));

    await show('LAST_KNOWN', fixAgeMs: 240000);
    expect(find.text('last known fix, 4 min old'), findsOneWidget);

    await show('FAILED');
    expect(find.text('no location'), findsOneWidget);

    await show('SLOW');
    expect(find.text('no location needed'), findsOneWidget);
  });

  testWidgets('marks a run 10 s late or more and a fix two intervals old', (tester) async {
    Color? colorOf(String text) => tester.widget<Text>(find.text(text)).style?.color;

    await tester.pumpWidget(tile(runRow(firedAt: firedAt, delayMs: 9999, fixAgeMs: 119999, accuracyM: null)));
    final warn = StatusColors.of(tester.element(find.byType(RunTile))).warn;
    expect(colorOf('10.0 s late'), isNot(warn));
    expect(find.text('fix 2 min old'), findsNothing);
    expect(colorOf('fix 1 min 59 s old'), isNot(warn));
    expect(find.byIcon(Icons.running_with_errors), findsNothing);

    await tester.pumpWidget(tile(runRow(firedAt: firedAt, delayMs: 240000, fixAgeMs: 120000, accuracyM: null)));
    expect(colorOf('4 min late'), warn);
    expect(find.byIcon(Icons.running_with_errors), findsOneWidget);
    expect(colorOf('stale fix, 2 min old'), warn);
  });

  testWidgets('shows a manual run that fired early and its error', (tester) async {
    await tester.pumpWidget(tile(
      runRow(firedAt: firedAt, trigger: 'manual', delayMs: -300, error: 'current: TimeoutException'),
    ));

    expect(find.text('manual'), findsOneWidget);
    expect(find.text('0.3 s early'), findsOneWidget);
    expect(find.text('current: TimeoutException'), findsOneWidget);
  });

  test('formats spans, countdowns, counts and days', () {
    expect(span(400), '0.4 s');
    expect(span(42000), '42 s');
    expect(span(192000), '3 min 12 s');
    expect(span(7500000), '2 h 5 min');
    expect(countdown(const Duration(seconds: 42)), '0:42');
    expect(countdown(const Duration(milliseconds: 400)), '0:01');
    expect(countdown(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    expect(countdown(Duration.zero), 'now');
    expect(count(1532), '1,532');
    expect(count(999), '999');
    expect(dayLabel(firedAt, firedAt), 'Today');
    expect(dayLabel(DateTime(2026, 11, 3, 23), firedAt), 'Yesterday');
    expect(dayLabel(DateTime(2026, 11, 2), firedAt), 'Mon 2 Nov');
  });
}
