import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';

import '../app_scope.dart';

/// The [FileSaver] the app uses: the system's save dialog, then a write to the place chosen.
Future<String?> saveWithDialog(
  String suggestedName,
  Future<List<int>?> Function() bytes,
) async {
  final FileSaveLocation? place;
  try {
    place = await getSaveLocation(suggestedName: suggestedName);
  } on UnimplementedError {
    throw Exception('This device cannot save a file this way.');
  }
  if (place == null) return null;
  final data = await bytes();
  if (data == null) return null;
  await XFile.fromData(Uint8List.fromList(data)).saveTo(place.path);
  return place.path;
}

/// Saves what [bytes] gives as [suggestedName] through [AppScope.save], and returns where, or
/// null. A failure shows as [failTitle] through [report], or in Files when it is null.
Future<String?> saveFile(
  BuildContext context,
  String suggestedName,
  Future<List<int>?> Function() bytes, {
  required String failTitle,
  void Function(String title, String text)? report,
}) async {
  final scope = AppScope.of(context);
  try {
    return await scope.save(suggestedName, bytes);
  } on Exception catch (error) {
    (report ?? scope.files.report)(failTitle, _plain(error));
    return null;
  }
}

/// [error]'s message without Dart's `Exception: ` prefix.
String _plain(Exception error) =>
    '$error'.replaceFirst(RegExp('^Exception: '), '');
