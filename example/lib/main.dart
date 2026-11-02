import 'dart:async';

import 'package:dozeless/dozeless.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'spike_db.dart';
import 'spike_jobs.dart';
import 'spike_row.dart';
import 'spike_stats.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Dozeless.initialize(
    stopNotification: const StopNotification(
      title: 'Spike berhenti',
      body: 'Buka dozeless example untuk memperbaiki izin atau baterai.',
      channelName: 'Status spike',
    ),
  );
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: SpikePage()));
}

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> with WidgetsBindingObserver {
  PrerequisiteStatus? _prereqs;
  JobStatus? _spike;
  JobStatus? _slow;
  List<SpikeRow> _rows = const [];
  Duration _window = const Duration(minutes: 90);
  Timer? _timer;

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
    final prereqs = await Dozeless.checkPrerequisites();
    final spike = await Dozeless.status(spikeJobId);
    final slow = await Dozeless.status(slowJobId);
    final rows = await SpikeDb.since(DateTime.now().subtract(const Duration(hours: 24)));
    if (!mounted) return;
    setState(() {
      _prereqs = prereqs;
      _spike = spike;
      _slow = slow;
      _rows = rows;
    });
  }

  Future<void> _act(Future<void> Function() action) async {
    await action();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final oldest = _rows.isEmpty ? now : DateTime.fromMillisecondsSinceEpoch(_rows.last.firedAt);
    final windowStart = now.subtract(_window);
    final from = oldest.isAfter(windowStart) ? oldest : windowStart;
    final stats = SpikeStats.compute(_rows, jobId: spikeJobId, interval: spikeInterval, from: from, to: now);
    final p = _prereqs;

    return Scaffold(
      appBar: AppBar(title: const Text('dozeless spike'), actions: [
        IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Prasyarat', style: Theme.of(context).textTheme.titleMedium),
          if (p != null) ...[
            _check('Lokasi', p.location),
            _check('Lokasi sepanjang waktu', p.backgroundLocation),
            _check('Baterai tidak dibatasi', p.batteryUnrestricted),
            _check('Tidak "Dibatasi"', !p.backgroundRestricted),
            _check('Exact alarm', p.exactAlarm),
            _check('Notifikasi', p.notification),
            if (p.forceStopGuardAvailable) _check('Pengaman force stop', p.forceStopGuard),
          ],
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: () => _act(Permission.location.request), child: const Text('Izin lokasi')),
            OutlinedButton(
                onPressed: () => _act(Permission.locationAlways.request), child: const Text('Lokasi sepanjang waktu')),
            OutlinedButton(onPressed: () => _act(Permission.notification.request), child: const Text('Notifikasi')),
            OutlinedButton(
                onPressed: () => _act(() => Dozeless.openSettings(Setting.batteryOptimization)),
                child: const Text('Optimasi baterai')),
            OutlinedButton(
                onPressed: () => _act(() => Dozeless.openSettings(Setting.appDetails)), child: const Text('App info')),
            if (p?.autostartSettingAvailable ?? false)
              OutlinedButton(
                  onPressed: () => _act(() => Dozeless.openSettings(Setting.autostart)), child: const Text('Autostart')),
            if ((p?.forceStopGuardAvailable ?? false) && !p!.forceStopGuard)
              OutlinedButton(
                  onPressed: () => _act(() => Dozeless.openSettings(Setting.forceStopGuard)),
                  child: const Text('Pengaman force stop')),
            if (p?.forceStopGuard ?? false)
              OutlinedButton(onPressed: () => _act(Dozeless.disableForceStopGuard), child: const Text('Matikan pengaman')),
          ]),
          const Divider(height: 32),
          Text('Job', style: Theme.of(context).textTheme.titleMedium),
          Text(_describe(spikeJobId, _spike)),
          Text(_describe(slowJobId, _slow)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(onPressed: () => _act(startSpike), child: const Text('Start')),
            OutlinedButton(onPressed: () => _act(stopSpike), child: const Text('Stop')),
            OutlinedButton(onPressed: () => _act(() => Dozeless.runNow(spikeJobId)), child: const Text('Jalankan sekarang')),
            OutlinedButton(
                onPressed: () => _act(() => Dozeless.debugFireIn(spikeJobId, const Duration(seconds: 10))),
                child: const Text('Alarm 10 detik lagi')),
            OutlinedButton(
                onPressed: () => _act(() async {
                      await Dozeless.debugSimulateLostAlarm(spikeJobId);
                      await Dozeless.debugRunWatchdog();
                    }),
                child: const Text('Simulasi alarm hilang')),
            OutlinedButton(onPressed: () => _act(SpikeDb.clear), child: const Text('Hapus baris')),
          ]),
          const Divider(height: 32),
          Text('Statistik spike', style: Theme.of(context).textTheme.titleMedium),
          Wrap(spacing: 8, children: [
            for (final minutes in [30, 90])
              ChoiceChip(
                label: Text('$minutes menit'),
                selected: _window.inMinutes == minutes,
                onSelected: (_) => setState(() => _window = Duration(minutes: minutes)),
              ),
          ]),
          Text('Diharapkan ${stats.expected} · jalan ${stats.ran} (${(stats.ranRatio * 100).toStringAsFixed(1)}%)'),
          Text('Median telat ${(stats.medianDelayMs / 1000).toStringAsFixed(1)} s · berlokasi ${stats.withLocation} '
              '· segar ${stats.withFreshLocation}'),
          Text(stats.passes ? 'LULUS' : 'BELUM LULUS',
              style: TextStyle(color: stats.passes ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
          const Divider(height: 32),
          Text('Baris terakhir', style: Theme.of(context).textTheme.titleMedium),
          for (final r in _rows.take(50))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${_clock(r.firedAt)}  ${r.jobId}/${r.trigger}'),
              subtitle: Text('telat ${(r.delayMs / 1000).toStringAsFixed(1)} s · '
                  'durasi ${((r.finishedAt - r.startedAt) / 1000).toStringAsFixed(1)} s · ${r.locationStatus}'
                  '${r.fixAgeMs == null ? '' : ' (umur ${r.fixAgeMs! ~/ 1000} s)'} · '
                  'idle ${r.deviceIdle} · ${r.standbyBucket}${r.events.isEmpty ? '' : ' · ${r.events}'}'),
            ),
        ],
      ),
    );
  }

  Widget _check(String label, bool ok) => Row(children: [
        Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.green : Colors.red, size: 18),
        const SizedBox(width: 8),
        Text(label),
      ]);

  String _describe(String id, JobStatus? s) {
    if (s == null) return '$id: belum dijadwalkan';
    final next = s.nextRunAt == null ? '-' : _clock(s.nextRunAt!.millisecondsSinceEpoch);
    final missing = s.missing.isEmpty ? '' : ' · kurang ${s.missing.map((m) => m.name).join(',')}';
    return '$id: ${s.mode.name} · next $next · run ${s.runCount} · busy ${s.skippedBusyCount}'
        '${s.lastError == null ? '' : ' · error ${s.lastError}'}$missing';
  }

  static String _clock(int epochMs) => DateTime.fromMillisecondsSinceEpoch(epochMs).toIso8601String().substring(11, 19);
}
