import 'package:intl/intl.dart';

String formatDateTime(DateTime? value) {
  if (value == null) return '--';
  return DateFormat('dd/MM/yyyy HH:mm').format(value);
}

String formatTime(DateTime? value) {
  if (value == null) return '--';
  return DateFormat('HH:mm').format(value);
}
