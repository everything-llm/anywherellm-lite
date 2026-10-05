import 'dart:convert';
import 'dart:io';

import '../core/models.dart';
import '../core/ports.dart';
import 'nils_command.dart';

/// Runs [executable] with [arguments] in [workingDirectory] and returns how it ended.
typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
});

/// [RunProcess] over `Process.run`.
Future<ProcessResult> runProcess(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) => Process.run(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  stdoutEncoding: utf8,
  stderrEncoding: utf8,
);

/// [NilsApi] over the `nils view` and `nils inbox add` commands, one process per call.
///
/// Each read prints one JSON value on stdout, in the shapes of src/nils/adapters/library/views.py.
/// A failure prints `error: ...` on stderr and exits 1; that text is what an [ApiException]
/// carries.
class CliNilsApi implements NilsApi {
  CliNilsApi(this.command, {RunProcess? run}) : _run = run ?? runProcess;

  final NilsCommand command;
  final RunProcess _run;

  // ---- reads ---------------------------------------------------------------------------------

  @override
  Future<Overview> overview() async =>
      Overview.fromJson(await _view(['overview']) as Json);

  @override
  Future<List<ResearchEntry>> research() async =>
      jsonList(await _view(['research']), ResearchEntry.fromJson);

  @override
  Future<ResearchDoc> researchDoc(String path) async =>
      ResearchDoc.fromJson(await _view(['research-doc', path]) as Json);

  @override
  Future<List<SkillMeta>> skills() async =>
      jsonList(await _view(['skills']), SkillMeta.fromJson);

  @override
  Future<SkillDoc> skillDoc(String name) async =>
      SkillDoc.fromJson(await _view(['skill-doc', name]) as Json);

  @override
  Future<List<String>> inbox() async =>
      (await _view(['inbox']) as List<dynamic>).cast<String>();

  // ---- writes --------------------------------------------------------------------------------

  /// Writes [bytes] to a file called [name] in a scratch directory and has `nils inbox add` stage
  /// a copy of it, so nils applies its own name and size rules.
  @override
  Future<void> upload(String name, List<int> bytes) async {
    final scratch = await Directory.systemTemp.createTemp('everything-');
    try {
      final file = File('${scratch.path}/$name');
      await file.writeAsBytes(bytes);
      await _call(['inbox', 'add', file.path]);
    } finally {
      await scratch.delete(recursive: true);
    }
  }

  // ---- plumbing ------------------------------------------------------------------------------

  Future<Object?> _view(List<String> arguments) async {
    final out = await _call(['view', ...arguments]);
    try {
      return jsonDecode(out);
    } on FormatException {
      throw const ApiException('nils answered with something that is not JSON');
    }
  }

  /// Runs `nils` with [subcommand] and returns its stdout, or throws what it said on stderr.
  Future<String> _call(List<String> subcommand) async {
    final ProcessResult result;
    try {
      result = await _run(
        command.executable,
        command.arguments(subcommand),
        workingDirectory: command.repo.path,
      );
    } on ProcessException catch (error) {
      throw ApiException(
        'could not run ${command.executable}: ${error.message}',
      );
    }
    if (result.exitCode != 0) throw ApiException(_said(result));
    return result.stdout as String;
  }

  /// What a failed command said: its `error: ` text, or the exit code when it said nothing.
  static String _said(ProcessResult result) {
    final text = (result.stderr as String).trim();
    if (text.isEmpty) return 'nils exited with code ${result.exitCode}';
    return text.startsWith('error: ') ? text.substring(7) : text;
  }
}
