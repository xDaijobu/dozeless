import 'package:dozeless_example/ui/model.dart';
import 'package:dozeless_example/ui/setup_checklist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('setupItemsFor', () {
    test('lists the needed prerequisites first, then the recommended ones', () {
      final items = setupItemsFor(prereqs());
      expect(items.map((i) => i.action), [
        SetupAction.location,
        SetupAction.backgroundLocation,
        SetupAction.batteryOptimization,
        SetupAction.appDetails,
        SetupAction.exactAlarm,
        SetupAction.notification,
      ]);
      expect(items.every((i) => i.state == SetupState.ok), isTrue);
      expect(setupProgress(items), '6 of 6 ready');
    });

    test('adds Autostart and the force-stop guard only when the device has them', () {
      final items = setupItemsFor(prereqs(autostartSettingAvailable: true, forceStopGuardAvailable: true));
      expect(items.map((i) => i.action), containsAllInOrder([SetupAction.autostart, SetupAction.forceStopGuard]));
      expect(items.firstWhere((i) => i.action == SetupAction.autostart).state, SetupState.unknown);
      expect(setupProgress(items), '6 of 7 ready');
    });

    test('a restricted app misses background usage, and background location waits for location', () {
      final items = setupItemsFor(prereqs(location: false, backgroundLocation: false, backgroundRestricted: true));
      SetupItem item(SetupAction a) => items.firstWhere((i) => i.action == a);
      expect(item(SetupAction.appDetails).state, SetupState.missing);
      expect(item(SetupAction.backgroundLocation).blockedBy, 'Allow location first');
      expect(setupProgress(items), '3 of 6 ready');
    });
  });

  group('SetupChecklist', () {
    Future<List<SetupAction>> pumpChecklist(WidgetTester tester, List<SetupItem> items) async {
      final fixed = <SetupAction>[];
      await tester.pumpWidget(themed(SetupChecklist(items: items, onFix: fixed.add)));
      return fixed;
    }

    testWidgets('shows every row with why it matters', (tester) async {
      final items = setupItemsFor(prereqs(autostartSettingAvailable: true, forceStopGuardAvailable: true));
      await pumpChecklist(tester, items);

      expect(find.text('Needed to run'), findsOneWidget);
      expect(find.text('Recommended'), findsOneWidget);
      for (final item in items) {
        expect(find.text(item.title), findsOneWidget);
        expect(find.text(item.why), findsOneWidget);
      }
    });

    testWidgets('has a Fix button only for missing rows', (tester) async {
      await pumpChecklist(tester, setupItemsFor(prereqs(batteryUnrestricted: false, notification: false)));

      expect(find.widgetWithText(FilledButton, 'Fix'), findsNWidgets(2));
      expect(find.byIcon(Icons.error), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(4));
    });

    testWidgets('Fix runs the matching action', (tester) async {
      final fixed = await pumpChecklist(tester, setupItemsFor(prereqs(batteryUnrestricted: false)));

      await tester.tap(find.widgetWithText(FilledButton, 'Fix'));
      expect(fixed, [SetupAction.batteryOptimization]);
    });

    testWidgets('Fix waits for location before asking for location all the time', (tester) async {
      final fixed = await pumpChecklist(tester, setupItemsFor(prereqs(location: false, backgroundLocation: false)));

      final buttons = find.widgetWithText(FilledButton, 'Fix');
      expect(buttons, findsNWidgets(2));
      expect(tester.widget<FilledButton>(buttons.at(1)).onPressed, isNull);
      expect(find.text('Allow location first'), findsOneWidget);

      await tester.tap(buttons.at(0));
      expect(fixed, [SetupAction.location]);
    });

    testWidgets('Autostart opens its page and app info is always one tap away', (tester) async {
      final fixed = await pumpChecklist(tester, setupItemsFor(prereqs(autostartSettingAvailable: true)));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Open'));
      await tester.ensureVisible(find.text('Open app info'));
      await tester.pump();
      await tester.tap(find.text('Open app info'));
      expect(fixed, [SetupAction.autostart, SetupAction.appDetails]);
    });
  });
}
