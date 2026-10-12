// Import direction for lib/: ui -> core <- adapters, composed only by main.dart.
//
// core is pure Dart. adapters own dart:io. ui owns Flutter. Neither
// ui nor adapters reaches into the other; main.dart wires them together. HTTP and the keyring are
// adapters' alone.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _forbidden = <String, List<String>>{
  'core': [
    'package:flutter/',
    'dart:io',
    'dart:ui',
    'package:file_picker',
    'package:mobile_scanner',
    'package:http/',
    'package:flutter_secure_storage',
    '/adapters/',
    '/ui/',
    '../adapters',
    '../ui',
  ],
  'adapters': [
    'package:flutter/',
    'dart:ui',
    'package:file_picker',
    'package:mobile_scanner',
    '/ui/',
    '../ui',
  ],
  'ui': [
    'dart:io',
    'package:http/',
    'package:flutter_secure_storage',
    '/adapters/',
    '../adapters',
  ],
};

final _import = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');

void main() {
  for (final entry in _forbidden.entries) {
    test('lib/${entry.key} imports stay inside its layer', () {
      final dir = Directory('lib/${entry.key}');
      if (!dir.existsSync()) return;
      final offenders = <String>[];
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        for (final line in file.readAsLinesSync()) {
          final target = _import.firstMatch(line)?.group(1);
          if (target == null) continue;
          if (entry.value.any(target.contains)) {
            offenders.add('${file.path}: $target');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });
  }
}
