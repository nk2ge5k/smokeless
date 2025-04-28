import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:smoke/storage.dart';
import 'package:smoke/chart/chart.dart';

class AverageTimeChart extends StatefulWidget {
  const AverageTimeChart({super.key});

  @override
  State<AverageTimeChart> createState() => _AverageTimeChartState();
}

class _AverageTimeChartState extends State<AverageTimeChart>
    with Loader<AverageTimeChart> {
  Map<int, double> data = {};

  @override
  Future<void> load() async {
    final avg = await Statistics().smokePerHour();
    if (mounted) setState(() => data = avg);
  }

  List<BarChartGroupData> _buildBars() {
    List<BarChartGroupData> bars = [];
    for (var i = 0; i <= 24; i++) {
      final count = data[i];
      bars.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              fromY: 0,
              toY: count ?? 0,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
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
    final maxY = data.entries.fold(0.0, (prev, e) => max(prev, e.value));

    return Chart(
      chartHeight: 150,
      title: 'Average cigarettes by time of day',
      description:
          'This chart displays your average cigarette consumption throughout '
          'the day, broken down by hour.',
      isLoading: isLoading,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY.toDouble(),
          groupsSpace: 0,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            drawHorizontalLine: true,
            checkToShowHorizontalLine: (value) => value == 0,
            getDrawingHorizontalLine: (value) {
              return FlLine(strokeWidth: 1, color: theme.highlightColor);
            },
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              direction: TooltipDirection.top,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final start = groupIndex.toInt();
                final end = start == 23 ? 0 : start + 1;
                final count = data[start] ?? 0;

                final startHour = start.toString().padLeft(2, '0');
                final endHour = end.toString().padLeft(2, '0');

                return BarTooltipItem(
                  "$startHour:00 - $endHour:00\n$count cigarettes",
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
                getTitlesWidget: (value, meta) => SizedBox.shrink(),
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
              bottom: BorderSide(width: 1, color: theme.highlightColor),
            ),
          ),
          barGroups: _buildBars(),
        ),
      ),
    );
  }
}
