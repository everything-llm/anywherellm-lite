// Wording, kept in one place so every part of the app says the same things.

/// `1 item`, `3 items`, `1,284 items`.
String plural(int count, String one, String many) =>
    '${grouped(count)} ${count == 1 ? one : many}';

/// [value] trimmed, or null when it is not text or holds only space.
String? textOrNull(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

/// [n] with commas between thousands: `1,284`.
String grouped(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

/// The months, shortened: `Jan` to `Dec`.
const monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// [at]'s time of day on a 24-hour clock: `07:05`.
String clockText(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
