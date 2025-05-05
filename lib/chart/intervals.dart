import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:smoke/storage.dart';
import 'package:smoke/utils.dart';
import 'package:smoke/chart/chart.dart';

class IntervalsChart extends StatefulWidget {
  final DateTime start;
  final DateTime end;

  const IntervalsChart({super.key, required this.start, required this.end});

  @override
  State<IntervalsChart> createState() => _IntervalsChartState();
}

class _IntervalsChartState extends State<IntervalsChart>
    with Loader<IntervalsChart> {
  List<IntervalItem> data = [];

  @override
  Future<void> load() async {
    final log = await Statistics().smokeIntervalHistory(
      widget.start,
      widget.end,
    );
    if (mounted) setState(() => data = log);
  }

  List<BarChartGroupData> _buildBars() {
    List<BarChartGroupData> bars = [];
    final radius = BorderRadius.only(
      topLeft: Radius.circular(6),
      topRight: Radius.circular(6),
    );

    for (var i = 0; i < data.length; i++) {
      final item = data[i];
      bars.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              fromY: 0,
              toY: item.interval.inSeconds / 60,
              color: Theme.of(context).primaryColor,
              borderRadius: radius,
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
    final maxY = data.fold(
      1.0,
      (prev, e) => max(prev, e.interval.inSeconds / 60),
    );
    final minY = data.fold(
      0.0,
      (prev, e) => min(prev, e.interval.inSeconds / 60),
    );

    return Chart(
      chartHeight: 200,
      title: 'Smoke-free intervals',
      description:
          'This chart displays the average time interval between cigarettes for '
          'each day of the week. It helps you monitor your daily smoking '
          'patterns and track progress in extending the time between cigarettes.',
      isLoading: isLoading,
      child: BarChart(
        BarChartData(
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawHorizontalLine: true,
            drawVerticalLine: false,
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
                final item = data[groupIndex];
                final textStyle = TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                );
                return BarTooltipItem(
                  "${formatDate(item.date)}\n ${item.interval.inMinutes} minutes",
                  textStyle,
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
                getTitlesWidget:
                    (value, meta) =>
                        Text(data[value.toInt()].date.day.toString()),
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
              bottom: BorderSide(width: 1, color: theme.highlightColor),
            ),
          ),
          barGroups: _buildBars(),
        ),
      ),
    );
  }
}
