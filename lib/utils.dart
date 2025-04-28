import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

DateTime startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime endOfDay(DateTime date) => startOfDay(date).add(Duration(hours: 24));
String formatTime(DateTime timestamp) => DateFormat('HH:mm').format(timestamp);
String formatDate(DateTime timestamp) => DateFormat('E d').format(timestamp);

mixin StateHelper<T extends StatefulWidget> on State<T> {
  // setStateSafe is the same thing as setState but it checks if component is
  // mounted before updating the state to avoid updates on the disposed component.
  void setStateSafe(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  // showMessage is a helper method that shows in the snackbar.
  void showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
