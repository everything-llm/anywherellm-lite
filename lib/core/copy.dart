// Wording, kept in one place so every part of the app says the same things.

/// `1 item`, `3 items`.
String plural(int count, String one, String many) =>
    '$count ${count == 1 ? one : many}';

/// [n] with commas between thousands: `1,284`.
String grouped(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
