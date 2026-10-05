// Wording, kept in one place so every part of the app says the same things.

/// `1 item`, `3 items`.
String plural(int count, String one, String many) =>
    '$count ${count == 1 ? one : many}';
