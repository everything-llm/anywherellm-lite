import 'package:flutter/painting.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/shell.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';

/// The languages a code block is coloured in, each with the names its fence may use.
final Highlight _highlight = Highlight()
  ..registerLanguages({
    'python': langPython,
    'dart': langDart,
    'javascript': langJavascript,
    'typescript': langTypescript,
    'json': langJson,
    'bash': langBash,
    'shell': langShell,
    'yaml': langYaml,
    'sql': langSql,
    'xml': langXml,
    'css': langCss,
    'java': langJava,
    'kotlin': langKotlin,
    'go': langGo,
    'rust': langRust,
    'c': langC,
    'cpp': langCpp,
    'csharp': langCsharp,
    'ruby': langRuby,
    'php': langPhp,
    'swift': langSwift,
    'markdown': langMarkdown,
    'diff': langDiff,
  });

/// The GitHub themes without their `root` style, so the code block keeps its own colours.
final _light = {...githubTheme}..remove('root');
final _dark = {...githubDarkTheme}..remove('root');

/// The spans [highlighted] made lately, so a block already coloured is not coloured again each
/// time a streaming answer rebuilds. The one used longest ago goes first past [_keep], so the
/// partial blocks of a streaming answer go before a finished block still on screen.
final _made = <(String, String, bool, TextStyle), TextSpan?>{};
const _keep = 64;

/// [code] coloured as [language], the name a Markdown fence gives, drawn over [base]; null when
/// no language is named or it is not one of the registered ones, so the code stays plain.
TextSpan? highlighted(
  String code,
  String? language, {
  required TextStyle base,
  required bool dark,
}) {
  if (language == null || _highlight.getLanguage(language) == null) return null;
  final key = (code, language.toLowerCase(), dark, base);
  if (_made.containsKey(key)) return _made[key] = _made.remove(key);
  if (_made.length >= _keep) _made.remove(_made.keys.first);
  return _made[key] = _colour(code, key.$2, base, dark ? _dark : _light);
}

TextSpan? _colour(
  String code,
  String language,
  TextStyle base,
  Map<String, TextStyle> theme,
) {
  try {
    final renderer = TextSpanRenderer(base, theme);
    _highlight.highlight(code: code, language: language).render(renderer);
    return renderer.span;
  } on Object {
    return null;
  }
}
