import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../core/files.dart';
import '../app_scope.dart';

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

/// Hands what [bytes] gives, named [name], to the system's share sheet through
/// [AppScope.share], where the device has one. [bytes] gives null, having said why, when there
/// is nothing to share; a share that fails shows through the chat's problem.
Future<void> shareFile(
  BuildContext context,
  String name,
  Future<List<int>?> Function() bytes,
) async {
  final scope = AppScope.of(context);
  final share = scope.share;
  if (share == null) return;
  final title = 'Could not share $name';
  try {
    final data = await bytes();
    if (data != null) await share(name, data);
  } on Exception catch (error) {
    scope.chat.report(title, _plain(error));
  }
}

/// Saves what [text] gives, the text the server read from the document called [title], under
/// [textFileName], as [saveFile] does.
Future<String?> saveText(
  BuildContext context,
  String title,
  Future<String> Function() text, {
  void Function(String title, String text)? report,
}) => saveFile(
  context,
  textFileName(title),
  () async => utf8.encode(await text()),
  failTitle: 'Could not save $title',
  report: report,
);

/// [error]'s message without Dart's `Exception: ` prefix.
String _plain(Exception error) =>
    '$error'.replaceFirst(RegExp('^Exception: '), '');
