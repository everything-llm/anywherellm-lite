import 'dart:io';

/// How to run `nils` in a checkout of the nils repository.
class NilsCommand {
  const NilsCommand(this.executable, this.prefix, this.repo);

  /// The program to start.
  final String executable;

  /// Arguments that come before the `nils` subcommand.
  final List<String> prefix;

  /// The checkout, where every command runs: nils finds its `storage/` from there.
  final Directory repo;

  List<String> arguments(List<String> subcommand) => [...prefix, ...subcommand];

  /// The checkout above any of [starts]: a directory holding `storage/data/research`, or a
  /// sibling named `nils` of one, which is where this app is developed.
  static Directory? findRepo(Iterable<Directory> starts) {
    for (final start in starts) {
      var dir = start.absolute;
      while (true) {
        for (final candidate in [dir, Directory('${dir.path}/nils')]) {
          if (Directory('${candidate.path}/storage/data/research')
              .existsSync()) {
            return candidate;
          }
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    return null;
  }

  /// The command for [repo]: its own virtualenv's `nils` when it has one, else `uv run nils`.
  static NilsCommand forRepo(Directory repo) {
    final venv = File('${repo.path}/.venv/bin/nils');
    if (venv.existsSync()) return NilsCommand(venv.path, const [], repo);
    return NilsCommand('uv', const ['run', 'nils'], repo);
  }
}
