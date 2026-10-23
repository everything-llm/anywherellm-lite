import 'dart:io';

/// How far the clock of the server that sent [headers] was ahead of the phone's as they came,
/// read from their `Date`, or null when there is none or it does not parse. `Date` is in whole
/// seconds.
Duration? skewOf(Map<String, String> headers) {
  final date = headers['date'];
  if (date == null) return null;
  try {
    return HttpDate.parse(date).difference(DateTime.now());
  } on FormatException {
    return null;
  } on HttpException {
    return null;
  }
}
