import 'package:dozeless/dozeless.dart';
import 'package:flutter/material.dart';

import 'format.dart';
import 'model.dart';
import 'theme.dart';

enum SetupState {
  ok,
  missing,

  /// Android can't report it (Autostart): the user has to look.
  unknown,
}

/// One row of the setup checklist.
class SetupItem {
  const SetupItem({
    required this.action,
    required this.title,
    required this.why,
    required this.state,
    required this.needed,
    this.blockedBy,
  });

  final SetupAction action;
  final String title;

  /// One line on why it matters.
  final String why;
  final SetupState state;

  /// Without it dozeless stops the jobs. The other rows make them better but not possible.
  final bool needed;

  /// Why Fix can't run yet, for example "Allow location first".
  final String? blockedBy;
}

/// The prerequisites of the example's jobs, needed ones first.
List<SetupItem> setupItemsFor(PrerequisiteStatus p) {
  SetupState of(bool ok) => ok ? SetupState.ok : SetupState.missing;
  return [
    SetupItem(
      action: SetupAction.location,
      title: 'Location',
      why: 'The spike job takes a location fix on every run.',
      state: of(p.location),
      needed: true,
    ),
    SetupItem(
      action: SetupAction.backgroundLocation,
      title: 'Location all the time',
      why: 'Without it Android blocks location while the app is in the background.',
      state: of(p.backgroundLocation),
      needed: true,
      blockedBy: p.location ? null : 'Allow location first',
    ),
    SetupItem(
      action: SetupAction.batteryOptimization,
      title: 'Battery not optimized',
      why: 'Optimized apps have their alarms deferred in Doze, so dozeless stops every job.',
      state: of(p.batteryUnrestricted),
      needed: true,
    ),
    SetupItem(
      action: SetupAction.appDetails,
      title: 'Background usage allowed',
      why: 'A restricted app gets no alarms in the background. Change it under Battery in app info.',
      state: of(!p.backgroundRestricted),
      needed: true,
    ),
    SetupItem(
      action: SetupAction.exactAlarm,
      title: 'Exact alarms',
      why: 'Without it the jobs keep running, but Android may move each run by minutes.',
      state: of(p.exactAlarm),
      needed: false,
    ),
    SetupItem(
      action: SetupAction.notification,
      title: 'Notifications',
      why: 'Lets dozeless tell you when the jobs stop because a setting is missing.',
      state: of(p.notification),
      needed: false,
    ),
    if (p.autostartSettingAvailable)
      const SetupItem(
        action: SetupAction.autostart,
        title: 'Autostart',
        why: 'Without it this brand may block the boot broadcast, so after a reboot the jobs wait until you open '
            'the app. Android can’t report it.',
        state: SetupState.unknown,
        needed: false,
      ),
    if (p.forceStopGuardAvailable)
      SetupItem(
        action: SetupAction.forceStopGuard,
        title: 'Force-stop guard',
        why: 'Greys out Force stop in Settings, so the jobs aren’t killed by accident.',
        state: of(p.forceStopGuard),
        needed: false,
      ),
  ];
}

/// The prerequisites with their status, why each matters and a button that fixes it.
class SetupChecklist extends StatelessWidget {
  const SetupChecklist({super.key, required this.items, required this.onFix});

  final List<SetupItem> items;
  final ValueChanged<SetupAction> onFix;

  @override
  Widget build(BuildContext context) {
    final needed = items.where((i) => i.needed).toList();
    final optional = items.where((i) => !i.needed).toList();
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (needed.isNotEmpty) ...[
          const _GroupLabel('Needed to run'),
          for (final item in needed) _SetupRow(item: item, onFix: onFix),
        ],
        if (optional.isNotEmpty) ...[
          const _GroupLabel('Recommended'),
          for (final item in optional) _SetupRow(item: item, onFix: onFix),
        ],
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => onFix(SetupAction.appDetails),
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Open app info'),
            ),
          ),
        ),
      ]),
    );
  }
}

/// "4 of 6 ready", for the section header.
String setupProgress(List<SetupItem> items) {
  final known = items.where((i) => i.state != SetupState.unknown);
  return '${count(known.where((i) => i.state == SetupState.ok).length)} of ${count(known.length)} ready';
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({required this.item, required this.onFix});

  final SetupItem item;
  final ValueChanged<SetupAction> onFix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    final (icon, color, label) = switch (item.state) {
      SetupState.ok => (Icons.check_circle, status.good, 'Done'),
      SetupState.missing when item.needed => (Icons.error, theme.colorScheme.error, 'Missing'),
      SetupState.missing => (Icons.radio_button_unchecked, status.warn, 'Not set'),
      SetupState.unknown => (Icons.help_outline, theme.colorScheme.onSurfaceVariant, 'Check yourself'),
    };
    final button = switch (item.state) {
      SetupState.ok => null,
      SetupState.missing => FilledButton.tonal(
          onPressed: item.blockedBy == null ? () => onFix(item.action) : null,
          child: const Text('Fix'),
        ),
      SetupState.unknown => OutlinedButton(onPressed: () => onFix(item.action), child: const Text('Open')),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, color: color, size: 22, semanticLabel: label),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(item.why, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (item.state == SetupState.missing && item.blockedBy != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(item.blockedBy!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
              ),
          ]),
        ),
        if (button != null) ...[const SizedBox(width: 12), button],
      ]),
    );
  }
}
