import 'package:intl/intl.dart';

final DateFormat shortDateFormat = DateFormat('dd/MM/yyyy');
final DateFormat dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

String formatDate(DateTime value) => shortDateFormat.format(value);

String formatDateTime(DateTime value) => dateTimeFormat.format(value);
