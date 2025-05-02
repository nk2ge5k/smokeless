import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For input formatters
import 'package:intl/intl.dart';

import 'package:smoke/storage.dart';
import 'package:smoke/utils.dart';
import 'package:smoke/dashboard.dart';

class Setup extends StatefulWidget {
  final bool isStartup;
  final void Function()? onSave;

  const Setup({super.key, required this.isStartup, this.onSave});

  @override
  State<Setup> createState() => _SetupState();
}

class _SetupState extends State<Setup> with StateHelper {
  final _formKey = GlobalKey<FormState>();
  final _limitController = TextEditingController();
  final _sleepController = TextEditingController();

  // Chart data
  List<FlSpot> _line = [];

  // Date when program starts
  DateTime _startDate = startOfDay(DateTime.now());
  // Current limit (loaded or set)
  int? _limit;
  // Is screen loading?
  bool _isLoading = true;

  // Database handler.
  final _statistics = Statistics();

  // -- Helpers --

  String _formatDate(DateTime timestamp) {
    return DateFormat('MMM d').format(timestamp);
  }

  Future<void> _loadInitialValue() async {
    try {
      final latest = await _statistics.limitLatest(DateTime.now());
      final sleepHours = await _statistics.sleepHours();
      if (mounted) {
        if (latest != null) _limitController.text = latest.$1.toString();
        _sleepController.text = sleepHours?.toString() ?? "8";
      }
    } catch (e) {
      showMessage("Failed to load saved settings");
    } finally {
      _updatePredictionChart(_startDate);
      setStateSafe(() => _isLoading = false);
    }

    _updatePredictionChart(_startDate);
  }

  void _updatePredictionChart(DateTime? date) {
    final count = int.tryParse(_limitController.text);
    if (count != null) {
      List<FlSpot> line = [];
      for (var limit = count; limit >= 0; limit--) {
        line.add(FlSpot(line.length.toDouble(), limit.toDouble()));
      }

      setStateSafe(() {
        _line = line;
        _limit = count;
        _startDate = date ?? startOfDay(DateTime.now());
      });
    } else {
      setStateSafe(() {
        _line = [];
        _limit = null;
        _startDate = date ?? startOfDay(DateTime.now());
      });
    }
  }

  // -- Actions --

  Future<void> _actionSumbmitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final int limit = int.parse(_limitController.text);
    final int sleepHours = int.parse(_sleepController.text);
    try {
      await _statistics.limitSave(DateTime.now(), limit);
      await _statistics.sleepHoursSave(sleepHours);

      if (widget.onSave != null) widget.onSave!.call();

      _goBack();
    } catch (e) {
      debugPrint('Error saving settings: $e');
      showMessage('Plan started successfully!');
    }
  }

  void _goBack() {
    if (mounted) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context, true);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(builder: (context) => Dashboard()),
        );
      }
    }
  }

  void _actionLimitCallback() {
    _updatePredictionChart(null);
  }

  // -- Widgets --

  Widget _widgetInput() {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          'How many cigarettes do you smoke per day on average?',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 15),
        TextFormField(
          controller: _limitController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Average cigarettes per day',
            border: OutlineInputBorder(),
            hintText: 'e.g., 15',
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter a number';
            }
            final number = int.tryParse(value);
            if (number == null || number <= 0) {
              return 'Please enter a valid number greater than 0';
            }
            if (number > 1440) {
              return 'No way you\'re smoking that much!';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        Text(
          'How many hours do you usually sleep per day?',
          style: theme.textTheme.titleMedium,
        ),
        Text(
          'This will help calculate the correct intervals between cigarettes.',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.secondary,
          ),
        ),
        const SizedBox(height: 15),
        TextFormField(
          controller: _sleepController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Hours of sleep per day',
            border: OutlineInputBorder(),
            hintText: 'e.g., 8',
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter a number';
            }
            final number = int.tryParse(value);
            if (number == null || number < 0 || 24 < number) {
              return 'Please enter a valid number between 0 and 24';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _widgetPrognosis() {
    final theme = Theme.of(context);

    if (_limit == null) {
      final textTheme = theme.textTheme;
      return Container(
        height:
            (textTheme.titleMedium?.fontSize ?? 0) +
            (textTheme.bodySmall?.fontSize ?? 0) +
            5 + // sized box
            15 + // sized box
            250 + // container height
            8, // unknonw spacing (probably line spacing)
      );
    }

    final quitDate = startOfDay(_startDate).add(Duration(days: _limit ?? 0));

    return Column(
      children: [
        Text(
          'Predicted Progress (Reduce by 1 every day)',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 5),
        Text(
          _limit != null
              ? 'Estimated date when you quit smoking is ${_formatDate(quitDate)}'
              : 'Enter average count to see prediction',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 15),
        Container(
          height: 250,
          padding: const EdgeInsets.only(top: 10, right: 10),
          child:
              _line.isEmpty
                  ? const Center(child: Text('Prediction will appear here'))
                  : _widgetPrognosisChart(),
        ),
      ],
    );
  }

  Widget _widgetPrognosisChart() {
    final theme = Theme.of(context);

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((LineBarSpot spot) {
                final date = _formatDate(
                  _startDate.add(Duration(days: spot.x.toInt())),
                );
                final textStyle = TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                );
                return LineTooltipItem(
                  "$date \n ${spot.y.toInt()} ${spot.y.toInt() == 1 ? 'cigarette' : 'cigarettes'}",
                  textStyle,
                );
              }).toList();
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 35),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: (_limit! / 2),
              getTitlesWidget:
                  (value, meta) => Container(
                    padding: const EdgeInsets.only(top: 10.0),
                    child: Text(
                      _formatDate(
                        _startDate.add(Duration(days: value.toInt())),
                      ),
                      style: TextStyle(
                        fontWeight:
                            value == 0 || value == _limit
                                ? FontWeight.bold
                                : FontWeight.normal,
                        color: Colors.black,
                      ),
                    ),
                  ),
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: _limit?.toDouble(),
        lineBarsData: [
          LineChartBarData(
            spots: _line,
            color: theme.primaryColor,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: theme.primaryColor.withAlpha(25),
            ),
          ),
        ],
      ),
      duration: Duration(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('Setup')),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                child: SizedBox(
                  height: media.size.height,
                  child: Form(
                    key: _formKey,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _widgetPrognosis(),
                          const SizedBox(height: 30),
                          _widgetInput(),
                          const SizedBox(height: 30),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              if (!widget.isStartup)
                                OutlinedButton(
                                  onPressed: _goBack,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.redAccent,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                      horizontal: 30,
                                    ),
                                  ),
                                  child: const Text('Cancel'),
                                ),
                              OutlinedButton(
                                onPressed: _actionSumbmitForm,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                    horizontal: 30,
                                  ),
                                ),
                                child: Text(Navigator.canPop(context) ? 'Save' : 'Start'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadInitialValue();
    _limitController.addListener(_actionLimitCallback);
  }

  @override
  void dispose() {
    _limitController.removeListener(_actionLimitCallback);
    _limitController.dispose();
    _sleepController.dispose();
    super.dispose();
  }
}
