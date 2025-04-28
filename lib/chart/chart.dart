import 'package:flutter/material.dart';

class Chart extends StatelessWidget {
  // Inner widget, that suppose to render chart.
  final Widget? child;
  // Chart height.
  final double chartHeight;

  // Title for the chart.
  final String? title;
  // Description for the chart.
  final String? description;
  // Is chart loading?
  final bool isLoading;

  const Chart({
    super.key,
    this.child,
    this.chartHeight = 150,
    this.title,
    this.description,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (title == null && description == null) {
      return SizedBox(height: chartHeight, child: child);
    }

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: EdgeInsets.only(bottom: 15),
            child: Text(
              title!,
              textAlign: TextAlign.left,
              style: theme.textTheme.titleMedium,
            ),
          ),
        SizedBox(
          height: chartHeight,
          child:
              isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : child,
        ),
        if (description != null) Text(description!),
      ],
    );
  }
}

typedef AsyncVoidCallback = Future<void> Function();

mixin Loader<T extends StatefulWidget> on State<T> {
  // isLoading is a flag that indicates if widget is loading
  bool isLoading = true;

  // Load function
  Future<void> load();

  Future<void> _load() async {
    if (mounted) {
      try {
         await load();
      } catch (e) {
        debugPrint("ERROR: Load data: $e");
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Failed to load chart data")));
        }
      } finally {
        if (mounted) setState(() => isLoading = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }
}
