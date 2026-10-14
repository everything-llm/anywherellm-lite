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

/// [value] decoded when it is text holding JSON, else [value] itself, as a field that some
/// servers send as JSON text and others as JSON.
Object? jsonOrSelf(Object? value) =>
    value is String ? jsonOrNull(value) ?? value : value;

/// [value] when it is text that is not empty, else null.
String? textOrNull(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// [value], ISO 8601 text, as a time in UTC, or null when it is not one.
DateTime? timeOrNull(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

/// An id given as a number or as text, as text, or null when there is none.
String? idOrNull(Object? value) => switch (value) {
  final int id => '$id',
  final String id when id.isNotEmpty => id,
  _ => null,
};

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
