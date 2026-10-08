// What an answer carries besides its text: files and images an agent made, and the numbers
// of how it ran.

/// A file or image an agent made with an answer. Its bytes come from the server by
/// [storageName], which the server gave it; [name] is what it is called for the person.
class GeneratedFile {
  const GeneratedFile({
    required this.type,
    required this.name,
    required this.storageName,
    this.size,
  });

  /// The server's kind of output, such as `imageGenerationCard` or `PdfFileDownload`.
  final String type;
  final String name;
  final String storageName;

  /// Its size in bytes, when the server gave one.
  final int? size;

  bool get isImage => type == 'imageGenerationCard';
}

/// The files in an answer's `outputs` list: each `{type, payload}` whose payload has a
/// `storageFilename` the server could have made, letters, digits, `_`, `.` and `-` only, so a
/// name can never reach outside the server's folder of generated files.
List<GeneratedFile> generatedFilesOf(Object? outputs) {
  if (outputs is! List) return const [];
  return [
    for (final output in outputs)
      if (output case {
        'type': final String type,
        'payload': final Map<String, dynamic> payload,
      })
        if (payload['storageFilename'] case final String storage
            when _storageName.hasMatch(storage))
          GeneratedFile(
            type: type,
            name: switch (payload['filename']) {
              final String name when name.trim().isNotEmpty => name.trim(),
              _ => storage,
            },
            storageName: storage,
            size: switch (payload['fileSize']) {
              final num size when size >= 0 => size.toInt(),
              _ => null,
            },
          ),
  ];
}

final _storageName = RegExp(r'^(?!\.+$)[\w.-]+$');

/// [bytes] in words: `812 B`, `14.2 KB` or `3.1 MB`.
String sizeText(int bytes) => switch (bytes) {
  < 1024 => '$bytes B',
  < 1024 * 1024 => '${(bytes / 1024).toStringAsFixed(1)} KB',
  _ => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
};

/// How an answer ran, as the server measured it. Any part may be missing.
class AnswerMetrics {
  const AnswerMetrics({
    this.model,
    this.tokens,
    this.seconds,
    this.speed,
    this.cost,
  });

  final String? model;

  /// The tokens the answer took.
  final int? tokens;
  final double? seconds;

  /// Tokens a second.
  final double? speed;

  /// What the answer cost, in dollars, when the server priced it.
  final double? cost;

  /// The parts in words, such as `glm-5.3 · 1,642 tokens · 22 tok/s · 73.9 s · $0.0049`.
  String get text => [
    ?model,
    if (tokens case final tokens?) '${_grouped(tokens)} tokens',
    if (speed case final speed?) '${speed.round()} tok/s',
    ?_seconds,
    if (cost case final cost?) '\$${cost.toStringAsFixed(cost < 1 ? 4 : 2)}',
  ].join(' · ');

  /// The model and the time alone, such as `glm-5.3 · 73.9 s`.
  String get brief => [?model, ?_seconds].join(' · ');

  /// Whether [text] says more than [brief].
  bool get hasMore => tokens != null || speed != null || cost != null;

  String? get _seconds =>
      seconds == null ? null : '${seconds!.toStringAsFixed(1)} s';
}

/// The `metrics` of an answer, or null when it has none: the server sends `{}` for an answer it
/// did not measure.
AnswerMetrics? metricsOf(Object? metrics) {
  if (metrics is! Map<String, dynamic>) return null;
  double? number(String key) => switch (metrics[key]) {
    final num n when n.isFinite && n >= 0 => n.toDouble(),
    _ => null,
  };
  final input = number('inputCost');
  final output = number('outputCost');
  final found = AnswerMetrics(
    model: switch (metrics['model']) {
      final String model when model.trim().isNotEmpty => model.trim(),
      _ => null,
    },
    tokens: number('completion_tokens')?.round(),
    seconds: number('duration'),
    speed: number('outputTps'),
    cost: input == null && output == null ? null : (input ?? 0) + (output ?? 0),
  );
  return found.text.isEmpty ? null : found;
}

/// [n] with commas between thousands: `1,642`.
String _grouped(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
