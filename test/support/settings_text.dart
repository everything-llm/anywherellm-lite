import 'dart:convert';

import 'package:anywherellm/core/server_models.dart';

const _indented = JsonEncoder.withIndent('  ');

/// [settings] as the JSON text the answer settings are parsed from, one key to a line.
String settingsText(WorkspaceSettings settings) =>
    '${_indented.convert(settings.values)}\n';
