import 'dart:async';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:smoke/storage.dart';
import 'package:smoke/utils.dart';
import 'package:smoke/setup.dart';
import 'package:smoke/chart/history.dart';
import 'package:smoke/chart/adherence.dart';
import 'package:smoke/chart/intervals.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> with StateHelper {
  // Amount of cigarettes smoked today.
  int _todayCount = 0;
  // Number of minutes that should be accouted for the sleep.
  int _sleepMinutes = 0;
  // Maximum allowed amount of cigarettes.
  int? _todayLimit;
  // Time when last cigarette was smoked if any.
  DateTime? _latestSmoke;

  // Timer that handles periodic screen updates.
  Timer? _timer;
  // Time when screen was loaded for the last.
  DateTime? _reloadAt;

  // Is dashboard data loading?
  bool _isLoading = true;

  // Database handler.
  final _statistics = Statistics();

  Future<void> _loadData() async {
    if (!mounted) return;

    final now = DateTime.now();

    try {
      final sleepHours = await _statistics.sleepHours() ?? 0;
      final todayCount = await _statistics.countSmokesDuring(now);
      final latestSmoke = await _statistics.latestSmoke(now);

      var limit = await _statistics.limitForDate(now);
      if (limit == null) {
        final latest = await _statistics.limitLatest(now);
        if (latest != null) {
          limit = max(latest.$1 - 1, 0);
          _statistics.limitSave(now, limit);
        }
      }

      setStateSafe(() {
        _todayCount = todayCount;
        _latestSmoke = latestSmoke;
        _todayLimit = limit;
        _reloadAt = DateTime.now();
        _sleepMinutes = sleepHours * 60;
      });
    } catch (e) {
      debugPrint("ERROR: Load data: $e");
      showMessage('Failed to load data');
    } finally {
      setStateSafe(() => _isLoading = false);
    }
  }

  // -- Helpers --

  DateTime _nextAllowed() {
    if (_latestSmoke == null || _todayLimit == null) {
      return DateTime.now();
    }

    final remaning = _todayLimit! - _todayCount;
    final dayEnd = endOfDay(_latestSmoke!);

    if (remaning <= 0) {
      return dayEnd.add(Duration(minutes: 1));
    }

    final dayLeft = dayEnd.difference(_latestSmoke!);
    final forSleep = _lerpDouble(0, _sleepMinutes, dayLeft.inMinutes / 1440);
    final left = dayLeft - Duration(minutes: forSleep.round());

    final avgIntervalMs = (left.inMilliseconds / remaning).round();
    final nextTimeMs = _latestSmoke!.millisecondsSinceEpoch + avgIntervalMs;

    var nextTime = DateTime.fromMillisecondsSinceEpoch(nextTimeMs);
    if (nextTime.compareTo(dayEnd) == -1) {
      nextTime = nextTime.add(Duration(minutes: 1));
    }

    return nextTime;
  }

  String _formatNextAllowed() {
    if (_latestSmoke == null || _todayLimit == null) {
      return "Whenever you're ready";
    }

    final remaning = _todayLimit! - _todayCount;
    if (remaning <= 0) {
      return "Not recommended";
    }

    final next = _nextAllowed();
    return formatTime(next);
  }

  // -- Actions --

  Future<void> _actionIncrementSmoked() async {
    HapticFeedback.vibrate();

    try {
      final now = DateTime.now();
      final next = _nextAllowed();

      final interval = next.difference(now);
      if (interval >= Duration(minutes: 5)) {
        return showDialog<void>(
          context: context,
          barrierDismissible: false, // user must tap button!
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Are you sure?'),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    interval < Duration(hours: 1)
                        ? Text(
                          'Consider waiting ${interval.inMinutes} more minutes?',
                          style: Theme.of(context).textTheme.bodyLarge,
                        )
                        : Text(
                          'Consider waiting until ${formatTime(next)}?',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: <Widget>[
                TextButton(
                  child: const Text('No', style: TextStyle(color: Colors.red)),
                  onPressed: () async {
                    if (mounted) Navigator.of(context).pop();
                    await _statistics.recordSmoke(now, next);
                    await _loadData();
                  },
                ),
                TextButton(
                  child: const Text('Okay, I’ll wait.'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            );
          },
        );
      }

      await _statistics.recordSmoke(now, next);
      await _loadData();
    } catch (e) {
      debugPrint("Error logging cigarette: $e");
      showMessage('Failed to record');
    }
  }

  Future<void> _actionDecrementSmoked() async {
    if (_todayCount <= 0) {
      return;
    }

    HapticFeedback.vibrate();

    final now = DateTime.now();

    try {
      final deleted = await _statistics.deleteLastSmoke(now);
      if (deleted > 0) await _loadData();
    } catch (e) {
      debugPrint("Error deleting last log: $e");
      showMessage('Failed to delete last record');
    }
  }

  // -- Widgets --

  Widget _widgetTodayGauge() {
    final count = _todayCount;
    final remaning = _todayLimit == null ? 0 : _todayLimit! - count;
    final bool isBelowTheLimit = _todayLimit != null && remaning > 0;
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 15.0),
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      child: Column(
        children: [
          SizedBox(
            height: media.size.height * 0.6,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 4,
                    centerSpaceRadius: media.size.width * 0.4,
                    startDegreeOffset: -90,
                    centerSpaceColor: theme.scaffoldBackgroundColor,
                    sections: [
                      PieChartSectionData(
                        color:
                            isBelowTheLimit
                                ? theme.primaryColor
                                : Colors.redAccent,
                        value: count.toDouble(),
                        radius: 25,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        color: theme.highlightColor,
                        value: remaning >= 0 ? remaning.toDouble() : 0,
                        radius: 20,
                        showTitle: false,
                      ),
                    ],
                    pieTouchData: PieTouchData(enabled: false),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                        children: [
                          TextSpan(text: '$count'),
                          TextSpan(
                            text:
                                _todayLimit == null ? '' : ' / ${_todayLimit!}',
                            style: TextStyle(
                              fontSize: 42,
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_latestSmoke != null)
                      RichText(
                        text: TextSpan(
                          style: TextStyle(fontSize: 16, color: Colors.black),
                          children: [
                            TextSpan(text: 'Last Smoked: '),
                            TextSpan(
                              text: formatTime(_latestSmoke!),
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),

                    if (_todayLimit != null)
                      RichText(
                        text: TextSpan(
                          style: TextStyle(fontSize: 16, color: Colors.black),
                          children: [
                            TextSpan(text: 'Next: '),
                            TextSpan(
                              text: _formatNextAllowed(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color:
                                    DateTime.now().compareTo(_nextAllowed()) < 0
                                        ? Colors.red
                                        : Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                iconSize: 50,
                color: count <= 0 ? Colors.grey : theme.colorScheme.primary,
                style: IconButton.styleFrom(
                  backgroundColor:
                      count <= 0
                          ? Colors.grey.shade300
                          : theme.colorScheme.surface,
                  side: BorderSide(color: theme.dividerColor),
                ),
                tooltip: 'Delete last smoked log',
                onPressed: _todayCount <= 0 ? null : _actionDecrementSmoked,
              ),
              const SizedBox(width: 30),
              IconButton(
                icon: const Icon(Icons.add),
                iconSize: 50,
                color: theme.colorScheme.primary,
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.surface,
                  side: BorderSide(color: theme.dividerColor),
                ),
                tooltip: 'Log a cigarette now',
                onPressed: _actionIncrementSmoked,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    _timer = Timer.periodic(Duration(minutes: 1), (Timer t) {
      final now = DateTime.now();
      if ((_reloadAt != null && _reloadAt!.day != now.day) ||
          _nextAllowed().compareTo(now) <= 1) {
        _loadData();
      }
    });

    _loadData();
  }

  @override
  void dispose() {
    if (_timer != null && _timer!.isActive) _timer!.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final now = startOfDay(DateTime.now());

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text("Today"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Open Settings',
            onPressed:
                () => {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => Setup(isStartup: false),
                    ),
                  ),
                },
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(
                      height: media.size.height * 0.9,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [_widgetTodayGauge()],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        spacing: 20,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20.0),
                            decoration: BoxDecoration(
                              color: theme.hoverColor,
                              borderRadius: BorderRadius.all(
                                Radius.circular(10),
                              ),
                            ),
                            child: Column(
                              spacing: 20,
                              children: [
                                Text(
                                  "Statistics",
                                  style: theme.textTheme.titleLarge,
                                ),
                                HistoryChart(
                                  key: Key("history_$_latestSmoke"),
                                  start: now.subtract(Duration(days: 7)),
                                  end: now,
                                ),
                                IntervalsChart(
                                  key: Key("intervals_$_latestSmoke"),
                                  start: now.subtract(Duration(days: 7)),
                                  end: now,
                                ),
                                AdherenceChart(
                                  key: Key("adherence_$_latestSmoke"),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}

double _lerpDouble(num a, num b, double t) {
  return a * (1.0 - t) + b * t;
}
