// The open workspace's pages, a file's name and bytes, and the answer settings as JSON.

import 'dart:typed_data';

import 'errors.dart';
import 'json.dart';
import 'server_models.dart';

/// The pages of the open workspace.
enum FilesSection {
  instructions('Instructions'),
  answers('Answer settings');

  const FilesSection(this.title);

  final String title;
}

final _notInFileName = RegExp(r'[\x00-\x1f/\\:*?"<>|]');

final _onlyDots = RegExp(r'^\.*$');

/// [name] as a file name that stays in the folder it is written in: any character a file name
/// cannot hold, a path separator among them, made `-`, so `../../prefs.json` becomes
/// `..-..-prefs.json`; [fallback] when nothing but dots is left.
String plainFileName(String name, {required String fallback}) {
  final plain = name.replaceAll(_notInFileName, '-').trim();
  return _onlyDots.hasMatch(plain) ? fallback : plain;
}

/// [bytes] as they are when they are already a [Uint8List], copied otherwise.
Uint8List bytesOf(List<int> bytes) =>
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

/// The settings in [text] that differ from [was], ready to write. Throws [ApiException] when the
/// text is not a JSON object, names a setting the app does not know, changes one it only reads,
/// such as the chat model, or gives one a value of the wrong type or range.
Map<String, Object?> parseSettings(String text, WorkspaceSettings was) {
  final changed = <String, Object?>{};
  for (final MapEntry(:key, :value) in settingsObject(text).entries) {
    final spec = workspaceSettingSpecs[key];
    if (spec == null) throw ApiException('$key is not a workspace setting.');
    if (value == was.values[key]) continue;
    if (spec.readOnly) {
      throw ApiException('$key is changed in AnythingLLM\'s web page.');
    }
    _check(key, spec, value);
    changed[key] = value;
  }
  return changed;
}

void _check(String key, SettingSpec spec, Object? value) {
  final choices = spec.choices;
  if (value == null && choices == null) return;
  if (spec.type == SettingType.text) {
    if (value is String && (choices == null || choices.contains(value))) {
      return;
    }
    throw ApiException(
      choices == null
          ? '$key must be text or null.'
          : '$key must be one of ${choices.join(', ')}.',
    );
  }
  final whole = spec.type == SettingType.integer;
  final max = spec.max;
  if ((whole ? value is int : value is num) &&
      (value as num) >= spec.min &&
      (max == null || value <= max)) {
    return;
  }
  final range = max == null
      ? 'of at least ${spec.min}'
      : 'from ${spec.min} to $max';
  throw ApiException(
    '$key must be ${whole ? 'a whole number' : 'a number'} $range.',
  );
}
