// JSON read defensively: text that is not JSON is something to refuse in plain words, not to
// crash on.

import 'dart:convert';

import 'errors.dart';

/// The decoded JSON of [text], or null when it is not JSON.
Object? jsonOrNull(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// The one JSON object in the settings [text] a person edited. Throws [ApiException] when the
/// text is not JSON, or is not an object.
Map<String, dynamic> settingsObject(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException catch (error) {
    throw ApiException('The settings are not valid JSON: ${error.message}');
  }
  if (json is! Map<String, dynamic>) {
    throw const ApiException('The settings must be one JSON object.');
  }
  return json;
}
