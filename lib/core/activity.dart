/// How long [span] is, as the shortest whole unit: `40 s`, `3 min`, `2 h` or `4 days`.
String elapsedText(Duration span) {
  final seconds = span.inSeconds < 0 ? 0 : span.inSeconds;
  if (seconds < 60) return '$seconds s';
  if (seconds < 3600) return '${seconds ~/ 60} min';
  if (seconds < 86400) return '${seconds ~/ 3600} h';
  return '${seconds ~/ 86400} ${seconds ~/ 86400 == 1 ? 'day' : 'days'}';
}

/// How long before [now] [at] was: `12 min ago`, `1 h ago`, `yesterday` or `2 days ago`.
String agoText(DateTime at, DateTime now) {
  final span = now.difference(at);
  if (span.inSeconds < 60) return 'just now';
  if (span.inHours >= 24 && span.inHours < 48) return 'yesterday';
  return '${elapsedText(span)} ago';
}
