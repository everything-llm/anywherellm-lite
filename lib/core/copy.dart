import 'dart:convert';

// Wording, kept in one place so every part of the app says the same things.

/// [text] with its first letter raised: `the Vault` as `The Vault`.
String capitalized(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

/// `1 item`, `3 items`, `1,284 items`.
String plural(int count, String one, String many) =>
    '${grouped(count)} ${count == 1 ? one : many}';

final _thousands = RegExp(r'\B(?=(\d{3})+$)');

/// [n] with commas between thousands: `1,284`.
String grouped(int n) => n.toString().replaceAllMapped(_thousands, (_) => ',');

/// The months, shortened: `Jan` to `Dec`.
const monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The days of the week, Monday first, as `DateTime.weekday - 1` indexes them.
const weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
  'Friday', 'Saturday', 'Sunday',
];

/// [items] as a sentence's list: `Mon`, `Mon and Wed`, `Mon, Wed and Fri`.
String andList(List<String> items) => items.length < 2
    ? items.join()
    : '${items.take(items.length - 1).join(', ')} and ${items.last}';

/// [at]'s time of day on a 24-hour clock: `07:05`.
String clockText(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

/// The line of a workspace's instructions that says what they are: the first one that is not
/// blank or only a markup tag, such as `<instructions version="3">`, or [text] whole when every
/// line is one.
String promptPreview(String text) {
  for (final line in const LineSplitter().convert(text)) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty && !_markupTag.hasMatch(trimmed)) return trimmed;
  }
  return text.trim();
}

final _markupTag = RegExp(r'^</?[\w:.-]+(\s[^>]*)?>$');
