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
  static const _titles = ['Dozeless Example', 'Runs', 'Lab'];

  Snapshot? _snapshot;

  /// Why the first load failed. Once a snapshot is shown, a failed refresh keeps it.
  Object? _loadError;

  /// Loads started so far. Only the latest one may update the screen.
  int _loads = 0;
  int _tab = 0;
  Timer? _timer;
  final _setupKey = GlobalKey();

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

  /// The timer, resume and actions can overlap; a load that finishes after a newer one started is dropped,
  /// so an older snapshot never replaces a newer one. With [report], a failed refresh says so.
  Future<void> _refresh({bool report = false}) async {
    final load = ++_loads;
    try {
      final snapshot = await _backend.load();
      if (!mounted || load != _loads) return;
      setState(() {
        _snapshot = snapshot;
        _loadError = null;
      });
    } catch (e) {
      debugPrint('dozeless example: refresh failed: $e');
      if (!mounted || load != _loads) return;
      if (_snapshot == null) {
        setState(() => _loadError = e);
      } else if (report) {
        _say('Couldn’t refresh: $e');
      }
    }
  }

  /// Pull to refresh and the refresh button.
  Future<void> _reload() => _refresh(report: true);

  void _retry() {
    setState(() => _loadError = null);
    _refresh();
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
      final problem = switch (await _backend.fix(action)) {
        FixResult.opened => null,
        FixResult.noPage => 'This phone has no ${action.label} page.',
        FixResult.wontAsk => 'Android won’t ask for ${action.label} again.',
      };
      if (problem != null) {
        _say(
          action == SetupAction.appDetails ? problem : '$problem Change it in app info.',
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

  /// Shows the Setup checklist on the Overview tab.
  void _showSetup() {
    setState(() => _tab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final setup = _setupKey.currentContext;
      if (setup == null || !setup.mounted) return;
      Scrollable.ensureVisible(setup, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    });
  }

  void _lab(LabAction action) {
    final (done, failed) = switch (action) {
      // Runs are serialized: a manual run waits for one already going, up to the slow job's 20 s.
      LabAction.runNow => ('Asked spike to run. It starts once no other run is busy.', 'Couldn’t run spike'),
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
        actions: [IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh))],
      ),
      body: switch ((snapshot, _loadError)) {
        (final Snapshot s, _) => _body(s),
        (null, final Object error) => _LoadError(error: error, onRetry: _retry),
        _ => const Center(child: CircularProgressIndicator()),
      },
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
      OverviewScreen(
        snapshot: snapshot,
        onRefresh: _reload,
        onStart: _start,
        onStop: _stop,
        onFix: _fix,
        onShowSetup: _showSetup,
        setupKey: _setupKey,
      ),
      RunsScreen(
        rows: snapshot.rows,
        jobs: JobsSummary(exampleJobs, snapshot.statuses, snapshot.prerequisites),
        now: now,
        onRefresh: _reload,
        onStart: _start,
        onShowSetup: _showSetup,
      ),
      LabScreen(
        rows: snapshot.rows,
        prerequisites: snapshot.prerequisites,
        spikeMode: snapshot.statuses[spikeJobInfo.id]?.mode,
        now: now,
        onRefresh: _reload,
        onAction: _lab,
        onOpen: _fix,
      ),
    ]);
  }
}

/// Shown when the very first load fails, so the app never spins forever.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text('Couldn’t read the job status', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            '$error',
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
        ]),
      ),
    );
  }
}
