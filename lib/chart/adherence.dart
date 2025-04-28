import 'dart:math';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:smoke/storage.dart';
import 'package:smoke/chart/chart.dart';

class AdherenceChart extends StatefulWidget {
  const AdherenceChart({super.key});

  @override
  State<AdherenceChart> createState() => _AdherenceChartState();
}

class _AdherenceChartState extends State<AdherenceChart>
    with Loader<AdherenceChart> {
  Map<int, Duration> data = {};

  DateTime _reloadAt = DateTime.now();
  Timer? _timer;

  @override
  Future<void> load() async {
    final delays = await Statistics().smokeAdherence(DateTime.now());

    if (mounted) {
      setState(() {
        data = delays;
        _reloadAt = DateTime.now();
      });
    }

    _timer ??= Timer.periodic(Duration(minutes: 1), (Timer t) {
      if (_reloadAt.day != DateTime.now().day) load();
    });
  }

  List<BarChartGroupData> _buildBars() {
    List<BarChartGroupData> bars = [];
    for (var i = 0; i <= 24; i++) {
      final delay = data[i];
      final minutes = delay != null ? delay.inMinutes : 0;

      final isTop = minutes > 0;

      final radius =
          isTop
              ? BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              )
              : BorderRadius.only(
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(6),
              );

      bars.add(
        BarChartGroupData(
          x: i,
          barRods: [
            isTop
                ? BarChartRodData(
                  fromY: minutes.toDouble(),
                  toY: 0,
                  borderRadius: radius,
                  color: Colors.cyan,
                )
                : BarChartRodData(
                  fromY: 0,
                  toY: minutes.toDouble(),
                  borderRadius: radius,
                  color: Colors.redAccent,
                ),
          ],
        ),
      );
    }

    return bars;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxY = data.entries.fold(
      1,
      (prev, e) => max(prev, e.value.inMinutes),
    );
    final minY = data.entries.fold(
      -1,
      (prev, e) => min(prev, e.value.inMinutes),
    );

    return Chart(
      chartHeight: 150,
      title: 'Schedule Adherence',
      description:
          'This visualization helps track how closely your actual smoking '
          'behavior aligns with your intended schedule throughout the day.',
      isLoading: isLoading,
      child: BarChart(
        BarChartData(
          minY: minY.toDouble(),
          maxY: maxY.toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) {
              if (value == 0) {
                return FlLine(strokeWidth: 1, color: theme.highlightColor);
              }
              return defaultGridLine(value);
            },
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              direction: TooltipDirection.top,
              getTooltipItem: (
                BarChartGroupData group,
                int groupIndex,
                BarChartRodData rod,
                int rodIndex,
              ) {
                final start = groupIndex.toInt();
                final end = start == 23 ? 0 : start + 1;
                final minutes =
                    data[start] != null ? data[start]!.inMinutes : 0;

                final startHour = start.toString().padLeft(2, '0');
                final endHour = end.toString().padLeft(2, '0');

                return BarTooltipItem(
                  "$startHour:00 - $endHour:00\n$minutes minutes",
                  TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 25,
                getTitlesWidget: (double value, TitleMeta meta) {
                  return (value == 0 || value == meta.max || value == meta.min)
                      ? Text(
                        "${value.abs().toInt()} min",
                        textScaler: TextScaler.linear(0.5),
                      )
                      : SizedBox.shrink();
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (double value, TitleMeta meta) {
                  if (value.toInt() % 6 == 0) {
                    return (value == 24)
                        ? Text("(h)")
                        : Text(value.toInt().toString());
                  }
                  return SizedBox.shrink();
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              left: BorderSide(width: 1, color: theme.highlightColor),
              bottom:
                  minY >= 0
                      ? BorderSide(width: 1, color: theme.highlightColor)
                      : BorderSide.none,
            ),
          ),
          barGroups: _buildBars(),
        ),
      ),
    );
  }
}
