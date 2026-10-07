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

/// [code] coloured as [language], the name a Markdown fence gives, drawn over [base]; null when
/// no language is named or it is not one of the registered ones, so the code stays plain.
TextSpan? highlighted(
  String code,
  String? language, {
  required TextStyle base,
  required bool dark,
}) {
  if (language == null || _highlight.getLanguage(language) == null) return null;
  final theme = {...(dark ? githubDarkTheme : githubTheme)}..remove('root');
  try {
    final renderer = TextSpanRenderer(base, theme);
    _highlight
        .highlight(code: code, language: language.toLowerCase())
        .render(renderer);
    return renderer.span;
  } on Object {
    return null;
  }
}
