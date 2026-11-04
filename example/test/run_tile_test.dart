import 'package:dozeless_example/ui/format.dart';
import 'package:dozeless_example/ui/run_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final firedAt = DateTime(2026, 11, 4, 14, 2, 13);

  testWidgets('shows time, job, trigger, delay, duration, fix, bucket and events', (tester) async {
    await tester.pumpWidget(themed(RunTile(
      row: runRow(firedAt: firedAt, delayMs: 1200, durationMs: 2100, fixAgeMs: 3000, events: 'boot,processExit'),
    )));

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
    await tester.pumpWidget(themed(RunTile(row: runRow(firedAt: firedAt))));
    expect(MediaQuery.textScalerOf(tester.element(find.byType(RunTile))).scale(10), closeTo(13, 0.01));

    final time = tester.renderObject<RenderParagraph>(find.text('14:02:13'));
    expect(time.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(time.size.width));
    expect(time.didExceedMaxLines, isFalse);
  });

  testWidgets('marks runs in Doze', (tester) async {
    await tester.pumpWidget(themed(RunTile(row: runRow(firedAt: firedAt, deviceIdle: true))));

    expect(find.text('Doze'), findsOneWidget);
    expect(find.byIcon(Icons.bedtime), findsOneWidget);
  });

  testWidgets('describes each location status', (tester) async {
    Future<void> show(String status, {int? fixAgeMs}) => tester.pumpWidget(themed(RunTile(
          row: runRow(firedAt: firedAt, locationStatus: status, fixAgeMs: fixAgeMs, accuracyM: null),
        )));

    await show('LAST_KNOWN', fixAgeMs: 240000);
    expect(find.text('last known fix, 4 min old'), findsOneWidget);

    await show('FAILED');
    expect(find.text('no location'), findsOneWidget);

    await show('SLOW');
    expect(find.text('no location needed'), findsOneWidget);
  });

  testWidgets('shows a manual run that fired early and its error', (tester) async {
    await tester.pumpWidget(themed(RunTile(
      row: runRow(firedAt: firedAt, trigger: 'manual', delayMs: -300, error: 'current: TimeoutException'),
    )));

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
