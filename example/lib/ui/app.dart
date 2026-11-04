import 'dart:async';

import 'package:flutter/material.dart';

import 'lab_screen.dart';
import 'model.dart';
import 'overview_screen.dart';
import 'runs_screen.dart';
import 'setup_checklist.dart';
import 'theme.dart';

class DozelessExampleApp extends StatelessWidget {
  const DozelessExampleApp({super.key, required this.backend});

  final ExampleBackend backend;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Dozeless Example',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: HomeShell(backend: backend),
      );
}

/// Loads a [Snapshot] on start, on resume and every 10 seconds, and runs the actions of all three tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.backend});

  final ExampleBackend backend;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  static const _titles = ['Dozeless example', 'Runs', 'Lab'];

  Snapshot? _snapshot;
  int _tab = 0;
  Timer? _timer;

  ExampleBackend get _backend => widget.backend;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final snapshot = await _backend.load();
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (e) {
      debugPrint('dozeless example: refresh failed: $e');
    }
  }

  /// Runs [action], says how it went, then refreshes.
  Future<void> _act(Future<void> Function() action, {required String done, required String failed}) async {
    try {
      await action();
      _say(done);
    } catch (e) {
      _say('$failed: $e');
    }
    await _refresh();
  }

  Future<void> _fix(SetupAction action) async {
    try {
      if (!await _backend.fix(action)) {
        _say(
          'Nothing opened for ${action.label}. Change it in app info instead.',
          action: action == SetupAction.appDetails
              ? null
              : SnackBarAction(label: 'App info', onPressed: () => _fix(SetupAction.appDetails)),
        );
      }
    } catch (e) {
      _say('Couldn’t open ${action.label}: $e');
    }
    await _refresh();
  }

  void _lab(LabAction action) {
    final (done, failed) = switch (action) {
      LabAction.runNow => ('Running spike now', 'Couldn’t run spike'),
      LabAction.fireIn10s => ('The next spike alarm fires in 10 s', 'Couldn’t move the alarm'),
      LabAction.simulateLostAlarm => ('Dropped the spike alarm and ran the watchdog', 'Couldn’t simulate a lost alarm'),
      LabAction.clearRows => ('Cleared all rows', 'Couldn’t clear the rows'),
      LabAction.disableForceStopGuard => ('Turned off the force-stop guard', 'Couldn’t turn off the guard'),
    };
    _act(() => _backend.lab(action), done: done, failed: failed);
  }

  void _start() => _act(_backend.startJobs, done: 'Started spike and slow', failed: 'Couldn’t start the jobs');

  void _stop() => _act(_backend.stopJobs, done: 'Stopped spike and slow', failed: 'Couldn’t stop the jobs');

  void _say(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), action: action));
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final open = snapshot == null
        ? 0
        : setupItemsFor(snapshot.prerequisites).where((i) => i.state == SetupState.missing && i.needed).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [IconButton(tooltip: 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: snapshot == null ? const Center(child: CircularProgressIndicator()) : _body(snapshot),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: Badge.count(count: open, isLabelVisible: open > 0, child: const Icon(Icons.space_dashboard_outlined)),
            selectedIcon: Badge.count(count: open, isLabelVisible: open > 0, child: const Icon(Icons.space_dashboard)),
            label: 'Overview',
          ),
          const NavigationDestination(icon: Icon(Icons.timeline), label: 'Runs'),
          const NavigationDestination(icon: Icon(Icons.science_outlined), selectedIcon: Icon(Icons.science), label: 'Lab'),
        ],
      ),
    );
  }

  Widget _body(Snapshot snapshot) {
    final now = DateTime.now();
    return IndexedStack(index: _tab, children: [
      OverviewScreen(snapshot: snapshot, onRefresh: _refresh, onStart: _start, onStop: _stop, onFix: _fix),
      RunsScreen(
        rows: snapshot.rows,
        scheduled: snapshot.statuses.isNotEmpty,
        now: now,
        onRefresh: _refresh,
        onStart: _start,
      ),
      LabScreen(
        rows: snapshot.rows,
        prerequisites: snapshot.prerequisites,
        now: now,
        onRefresh: _refresh,
        onAction: _lab,
        onOpen: _fix,
      ),
    ]);
  }
}
