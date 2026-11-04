import 'package:dozeless_example/ui/countdown.dart';
import 'package:dozeless_example/ui/format.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ticks every second until the target', (tester) async {
    var now = DateTime(2026, 11, 4, 14);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Countdown(
        target: now.add(const Duration(seconds: 2)),
        clock: () => now,
        builder: (context, left) => Text(countdown(left)),
      ),
    ));
    expect(find.text('0:02'), findsOneWidget);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:01'), findsOneWidget);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('now'), findsOneWidget);
  });
}
