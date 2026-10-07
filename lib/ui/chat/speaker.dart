import 'package:flutter/foundation.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/chat.dart';
import '../state/chat_controller.dart';

/// Reads text aloud with the device's own speech.
abstract interface class Speaker {
  /// Reads [text] aloud, stopping anything read before. Resolves when the reading ends, whether
  /// it finished or [stop] ended it. Throws [Exception] when the device cannot speak.
  Future<void> speak(String text);

  /// Ends the reading.
  Future<void> stop();
}

/// Which answer is being read aloud, if any. One reads at a time, and it stops when its answer
/// leaves the screen: another chat, workspace or server is shown.
class ReadAloud extends ChangeNotifier {
  ReadAloud(this._speaker, this._chat) {
    _chat.addListener(_follow);
  }

  final Speaker _speaker;
  final ChatController _chat;

  /// The answer being read.
  Turn? reading;

  /// Reads [turn]'s answer, without its reasoning or Markdown, or stops it when it is the one
  /// being read. A failure shows as the chat's problem.
  Future<void> toggle(Turn turn) async {
    if (identical(reading, turn)) return stop();
    reading = turn;
    notifyListeners();
    try {
      await _speaker.speak(plainText(splitReasoning(turn.text).answer));
    } on Exception catch (error) {
      if (identical(reading, turn)) {
        _chat.report(
          'Could not read the answer aloud',
          '$error'.replaceFirst(RegExp('^Exception: '), ''),
        );
      }
    }
    if (identical(reading, turn)) {
      reading = null;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    if (reading == null) return;
    reading = null;
    notifyListeners();
    await _speaker.stop();
  }

  void _follow() {
    if (reading case final turn? when !_chat.turns.contains(turn)) stop();
  }

  @override
  void dispose() {
    _chat.removeListener(_follow);
    _speaker.stop();
    super.dispose();
  }
}

/// [markdown] as the words a person would read: no markup, a link as its text, and each block
/// on its own line.
String plainText(String markdown) {
  final lines = <String>[];
  void walk(List<md.Node> nodes) {
    for (final node in nodes) {
      if (node is md.Element &&
          _holdsBlocks.contains(node.tag) &&
          (node.children ?? const []).any(
            (child) => child is md.Element && _blocks.contains(child.tag),
          )) {
        walk(node.children ?? const []);
      } else if (node.textContent.trim() case final line when line.isNotEmpty) {
        lines.add(line);
      }
    }
  }

  walk(
    md.Document(extensionSet: md.ExtensionSet.gitHubFlavored).parse(markdown),
  );
  return lines.join('\n');
}

/// The Markdown elements that start a line of their own.
const _blocks = {
  ..._holdsBlocks,
  'p',
  'pre',
  'tr',
  'hr',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
};

/// The Markdown elements made of other blocks, whose blocks are each read as a line. One that
/// holds only text, such as a list item of a few words, is read as one line.
const _holdsBlocks = {
  'ul',
  'ol',
  'li',
  'blockquote',
  'table',
  'thead',
  'tbody',
};
