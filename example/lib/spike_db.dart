import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'spike_row.dart';

/// Rows written by background jobs and read by the UI.
class SpikeDb {
  static Database? _db;

  static Future<Database> _open() async => _db ??= await openDatabase(
        p.join(await getDatabasesPath(), 'spike.db'),
        version: 1,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE rows(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            jobId TEXT NOT NULL, trigger TEXT NOT NULL,
            scheduledAt INTEGER NOT NULL, firedAt INTEGER NOT NULL, delayMs INTEGER NOT NULL,
            startedAt INTEGER NOT NULL, finishedAt INTEGER NOT NULL,
            lat REAL, lon REAL, accuracyM REAL, fixAgeMs INTEGER, locationStatus TEXT NOT NULL,
            deviceIdle INTEGER NOT NULL, interactive INTEGER NOT NULL, standbyBucket TEXT NOT NULL,
            mode TEXT NOT NULL, batteryUnrestricted INTEGER NOT NULL, events TEXT NOT NULL, error TEXT
          )'''),
      );

  static Future<void> insert(SpikeRow row) async => (await _open()).insert('rows', row.toMap());

  /// Newest first.
  static Future<List<SpikeRow>> since(DateTime from) async => [
        for (final m in await (await _open()).query(
          'rows',
          where: 'firedAt >= ?',
          whereArgs: [from.millisecondsSinceEpoch],
          orderBy: 'firedAt DESC',
        ))
          SpikeRow.fromMap(m),
      ];

  static Future<void> clear() async => (await _open()).delete('rows');
}
