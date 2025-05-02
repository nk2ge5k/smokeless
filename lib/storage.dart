import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:smoke/utils.dart';

class StatisticsItem {
  // Date
  final DateTime date;
  // Number of smoked cigarettes.
  final int smoked;
  // Limit for given date.
  final int? limit;

  const StatisticsItem({required this.date, required this.smoked, this.limit});
}

class IntervalItem {
  final DateTime date;
  final Duration interval;

  const IntervalItem({required this.date, required this.interval});
}

class Statistics {
  static final Statistics _statistics = Statistics._internal();

  static Database? _db;

  factory Statistics() {
    return _statistics;
  }

  Statistics._internal();

  Future<Database> get database async {
    if (_db != null) return _db!;
    // Initialize the DB first time it is accessed
    _db = await _create();
    return _db!;
  }

  Future<Database> _create() async {
    final databasePath = join(await getDatabasesPath(), 'statistics.db');

    // Set the version. This executes the onCreate function and provides a
    // path to perform database upgrades and downgrades.
    return await openDatabase(
      databasePath,
      onCreate: _initDatabase,
      onUpgrade: (db, oldVersion, newVersion) => _initDatabase(db, newVersion),
      version: 6,
    );
  }

  Future<void> _initDatabase(Database db, int version) async {
    await db.execute("""
      CREATE TABLE IF NOT EXISTS log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        -- Time when cigarette smoked
        timestamp INTEGER NOT NULL,
        -- Planned time
        plan_timestamp INTEGER
      );
      """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS limits (
        -- Date in format YYYYMMDD
        date INTEGER PRIMARY KEY NOT NULL,
        -- Limit
        value INTEGER NOT NULL
      );
      """);

    await db.execute("""
      CREATE TABLE IF NOT EXISTS settings (
        name TEXT PRIMARY KEY,
        value TEXT
      );
    """);
  }

  // recordSmoke creates a record for a smoked cigarette at given time.
  // @note: this method accepts time for the future proofing, but it is a bit
  // unnecessary.
  Future<void> recordSmoke(DateTime at, DateTime? plan) async {
    final database = await _statistics.database;
    await database.insert("log", {
      "timestamp": _toUnix(at),
      "plan_timestamp": plan != null ? _toUnix(plan) : null,
    });
  }

  // deleteLastSmoke delete latest smoke record for the given date.
  Future<int> deleteLastSmoke(DateTime date) async {
    final database = await _statistics.database;
    final (begin, end) = _dayBeginEndUnix(date);

    return await database.rawDelete(
      """
      DELETE FROM log WHERE rowid = (
        SELECT
          rowid
        FROM
          log
        WHERE
          timestamp BETWEEN ? AND ?
        ORDER BY timestamp DESC LIMIT 1
      )
      """,
      [begin, end],
    );
  }

  // countSmokesDuring returns number of cigarettes smoked on the given date.
  Future<int> countSmokesDuring(DateTime date) async {
    final database = await _statistics.database;
    final (begin, end) = _dayBeginEndUnix(date);

    return Sqflite.firstIntValue(
      await database.rawQuery(
        """
      SELECT
        COUNT(*) AS count
      FROM
        log
      WHERE
        timestamp BETWEEN ? AND ?
      """,
        [begin, end],
      ),
    )!;
  }

  // latestSmoke returns time of latest cigarette if any.
  Future<DateTime?> latestSmoke(DateTime date) async {
    final database = await _statistics.database;
    final (begin, end) = _dayBeginEndUnix(date);

    final result = await database.query(
      'log',
      columns: ['timestamp'],
      where: 'timestamp BETWEEN ? AND ?',
      whereArgs: [begin, end],
      orderBy: 'timestamp DESC', // Order by time, latest first
      limit: 1,
    );
    if (result.isNotEmpty) {
      final int timestamp = result.first['timestamp'] as int;
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    return null;
  }

  Future<Map<int, Duration>> smokeAdherence(DateTime date) async {
    final database = await _statistics.database;
    final offset = DateTime.now().timeZoneOffset.inHours;
    final (begin, end) = _dayBeginEndUnix(date);

    final result = await database.rawQuery(
      """
      SELECT
         strftime('%H', timestamp / 1000, 'unixepoch') as hour,
         avg(timestamp - coalesce(plan_timestamp, timestamp)) / 1000 as seconds
      FROM log
      WHERE
          timestamp BETWEEN ? AND ?
      GROUP BY hour
      """,
      [begin, end],
    );

    Map<int, Duration> hourSeconds = {};
    for (final item in result.toList()) {
      final idx = int.tryParse(item['hour'].toString());
      if (idx != null) {
        final hour = _wrap(idx + offset, 0, 24);
        hourSeconds[hour] = Duration(
          seconds: (item['seconds'] as double).toInt(),
        );
      }
    }

    return hourSeconds;
  }

  Future<int> smokeAverageInterval(DateTime date) async {
    final database = await _statistics.database;
    final (begin, end) = _dayBeginEndUnix(date);

    final result = await database.rawQuery(
      """
      SELECT 
        (avg(interval) / 1000) as interval 
      FROM (
        SELECT
          timestamp - lag(timestamp) over (order by timestamp) as interval
        FROM log
        WHERE
            timestamp BETWEEN ? AND ?
      );
      """,
      [begin, end],
    );

    if (result.isEmpty) {
      return 0;
    }

    return (result.first['interval'] as double? ?? 0.0).toInt();
  }

  Future<List<IntervalItem>> smokeIntervalHistory(
    DateTime startDate,
    DateTime endDate,
  ) async {
    if (startDate.compareTo(endDate) >= 0) {
      return <IntervalItem>[];
    }

    final start = startOfDay(startDate);
    final end = endOfDay(endDate);

    List<IntervalItem> result = [];

    // @slow: It would be better to use SQLite aggregation, but I wanted
    // to see the result without spending too much time researching SQLite's
    // aggregation and join functionality.
    for (
      var current = start;
      current.compareTo(end) == -1;
      current = current.add(Duration(hours: 24))
    ) {
      try {
        final seconds = await smokeAverageInterval(current);
        if (seconds != 0) {
          result.add(
            IntervalItem(date: current, interval: Duration(seconds: seconds)),
          );
        }
      } catch (e) {
        debugPrint("Failed to load data for day $current: $e");
      }
    }

    return result;
  }

  Future<Map<int, Duration>> smokeAvgDelay() async {
    final database = await _statistics.database;
    final offset = DateTime.now().timeZoneOffset.inHours;

    final result = await database.rawQuery("""
      SELECT
         strftime('%H', timestamp / 1000, 'unixepoch') as hour,
         avg((timestamp - coalesce(plan_timestamp, timestamp)) / 1000) as seconds
      FROM log
      GROUP BY hour
    """);

    Map<int, Duration> hourSeconds = {};
    for (final item in result.toList()) {
      final idx = int.tryParse(item['hour'].toString());
      if (idx != null) {
        final hour = _wrap(idx + offset, 0, 24);
        hourSeconds[hour] = Duration(
          seconds: (item['seconds'] as double).toInt(),
        );
      }
    }

    return hourSeconds;
  }

  Future<Map<int, double>> smokePerHour() async {
    final database = await _statistics.database;
    final offset = DateTime.now().timeZoneOffset.inHours;

    final result = await database.rawQuery("""
      SELECT
        hour,
        AVG(count) as count
      FROM (
        SELECT
           strftime('%Y%m%d', timestamp / 1000, 'unixepoch') as date,
           strftime('%H', timestamp / 1000, 'unixepoch') as hour,
           COUNT(timestamp) as count
        FROM log
        GROUP BY date, hour
      ) GROUP BY hour
    """);

    Map<int, double> hourCount = {};
    for (final item in result.toList()) {
      final idx = int.tryParse(item['hour'].toString());
      if (idx != null) {
        final hour = _wrap(idx + offset, 0, 24);
        hourCount[hour] = item['count'] as double;
      }
    }

    return hourCount;
  }

  // smokeLog returns a list dates with number of cigarettes smoked on each
  // given date.
  // @note: method ignores time value from the startDate and endDate.
  Future<List<StatisticsItem>> smokeLog(
    DateTime startDate,
    DateTime endDate,
  ) async {
    if (startDate.compareTo(endDate) >= 0) {
      return <StatisticsItem>[];
    }

    final start = startOfDay(startDate);
    final end = endOfDay(endDate);

    List<StatisticsItem> result = [];

    // @slow: It would be better to use SQLite aggregation, but I wanted
    // to see the result without spending too much time researching SQLite's
    // aggregation and join functionality.
    for (
      var current = start;
      current.compareTo(end) == -1;
      current = current.add(Duration(hours: 24))
    ) {
      try {
        final count = await countSmokesDuring(current);
        final limit = await limitForDate(current);

        if (count != 0) {
          result.add(
            StatisticsItem(date: current, smoked: count, limit: limit),
          );
        }
      } catch (e) {
        debugPrint("Failed to load data for day $current: $e");
        result.add(StatisticsItem(date: current, smoked: 0));
      }
    }

    return result;
  }

  // limitLatest returns latest limit
  Future<(int, DateTime)?> limitLatest(DateTime date) async {
    final database = await _statistics.database;
    final result = await database.query(
      'limits',
      columns: ['value', 'date'],
      where: 'date <= ?',
      whereArgs: [_dateToInt(date)],
      orderBy: 'date DESC', // Order by time, latest first
      limit: 1,
    );
    if (result.isEmpty) {
      return null;
    }

    final first = result.first;
    return (first['value'] as int, _dateFromInt(first['date'] as int));
  }

  // limitForDate returns limit for given date or null.
  Future<int?> limitForDate(DateTime date) async {
    final database = await _statistics.database;

    final result = await database.query(
      'limits',
      columns: ['value'],
      where: 'date = ?',
      whereArgs: [_dateToInt(date)],
      limit: 1,
    );

    return Sqflite.firstIntValue(result);
  }

  // limitSave save limit for the given date
  Future<void> limitSave(DateTime date, int limit) async {
    final database = await _statistics.database;
    await database.insert('limits', {
      'date': _dateToInt(date),
      'value': limit,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> sleepHoursSave(int hours) async {
    final database = await _statistics.database;
    await database.insert("settings", {
      "name": "sleep_hours",
      "value": hours.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int?> sleepHours() async {
    final database = await _statistics.database;
    final result = await database.query(
      "settings",
      columns: ["value"],
      where: "name = 'sleep_hours'",
    );

    if (result.isNotEmpty) {
      return int.tryParse(result.first["value"].toString());
    }
    return null;
  }
}

(int, int) _dayBeginEndUnix(DateTime date) {
  final start = startOfDay(date);
  final end = start.add(Duration(hours: 24));
  return (_toUnix(start), _toUnix(end));
}

int _toUnix(DateTime time) => time.millisecondsSinceEpoch;

int _dateToInt(DateTime date) =>
    (date.year * 10000) + (date.month * 100) + date.day;

DateTime _dateFromInt(int value) {
  var source = value;
  final year = (source / 10000).toInt();
  source -= year * 10000;
  final month = (source / 100).toInt();
  source -= month * 100;
  return DateTime(year.toInt(), month.toInt(), source.toInt());
}

// Wrap input value from min to max
int _wrap(int value, int min, int max) {
  return value - (max - min) * ((value - min) / (max - min)).floor();
}
