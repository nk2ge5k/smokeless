import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:smoke/storage.dart';
import 'package:smoke/utils.dart';
import 'package:smoke/chart/chart.dart';

class HistoryChart extends StatefulWidget {
  final DateTime start;
  final DateTime end;

  const HistoryChart({super.key, required this.start, required this.end});

  @override
  State<HistoryChart> createState() => _HistoryChartState();
}

class _HistoryChartState extends State<HistoryChart> with Loader<HistoryChart> {
  List<StatisticsItem> data = [];

  @override
  Future<void> load() async {
    final log = await Statistics().smokeLog(widget.start, widget.end);
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
      List<BarChartRodData> rods = [];
      if (item.limit == null) {
        rods.add(
          BarChartRodData(
            fromY: 0,
            toY: item.smoked.toDouble(),
            color: Colors.grey,
            borderRadius: radius,
          ),
        );
      } else {
        rods.add(
          BarChartRodData(
            fromY: 0,
            toY: item.limit!.toDouble(),
            color: Colors.red,
            borderRadius: radius,
          ),
        );
        rods.add(
          BarChartRodData(
            fromY: 0,
            toY: item.smoked.toDouble(),
            color: Theme.of(context).primaryColor,
            borderRadius: radius,
          ),
        );
      }
      bars.add(BarChartGroupData(x: i, barRods: rods));
    }

    return bars;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxY = data.fold(
      3,
      (prev, e) => max(prev, max(e.smoked, e.limit ?? 0)),
    );

    return Chart(
      chartHeight: 200,
      title: 'Last 7 days',
      description:
          'This chart displays your daily cigarette consumption over the '
          'past 7 days. It helps you track smoking patterns throughout the '
          'week and monitor your progress toward consumption goals.',
      isLoading: isLoading,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY.toDouble(),
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
                  item.limit == null
                      ? "${formatDate(item.date)}\n ${item.smoked} cigarettes"
                      : "${formatDate(item.date)}\n ${item.smoked}/${item.limit!} cigarettes",
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
                getTitlesWidget:
                    (value, meta) => Text((value.toInt()).toString()),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget:
                    (value, meta) => Text(formatDate(data[value.toInt()].date)),
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
