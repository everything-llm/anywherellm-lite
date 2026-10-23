import 'copy.dart';
import 'skill_pages.dart';

/// A tab of the agent's browser the bridge's `GET /pages` lists under `browser`: its page's
/// [path], `/browser-lean/<token>.html`, the [workspace] whose chat opened it, and when that
/// workspace's browser closes ([until], on the phone's clock). Every tab of a workspace closes
/// together. The path is a bearer capability: it is held in memory only, never logged, kept or
/// persisted.
class OpenTab {
  const OpenTab({
    required this.path,
    required this.workspace,
    required this.until,
  });

  final String path;
  final String workspace;
  final DateTime until;
}

/// The slack a closing time is given where it may be up to a minute early: the bridge relists a
/// tab only when its `until` moves a minute or more, and with no `Date` from the server the
/// phone's clock stands in for the server's.
const untilGrace = Duration(minutes: 1);

/// [until], ms since 1970 on the server's clock, on the phone's, given the server's clock was
/// [skew] ahead of it.
DateTime _onPhone(int until, Duration? skew) =>
    DateTime.fromMillisecondsSinceEpoch(
      until,
      isUtc: true,
    ).subtract(skew ?? Duration.zero);

final _slug = RegExp(r'^[A-Za-z0-9_-]{1,100}$');

/// The tabs a `GET /pages` answer's `browser` [list] names, in its order, newest drawn first,
/// their closing times on the phone's clock with [untilGrace] added, the server's clock [skew]
/// ahead of it; null when it is not a list, which means the bridge does not say. An entry
/// counts only with a browser-lean tab's path ([skillPageAt]), a workspace slug and a positive
/// whole `until`.
List<OpenTab>? openTabsOf(Object? list, {Duration? skew}) => list is! List
    ? null
    : [
        for (final entry in list)
          if (entry
              case {
                'path': final String path,
                'workspace': final String workspace,
                'until': final int until,
              }
              when until > 0 &&
                  _slug.hasMatch(workspace) &&
                  skillPageAt(path) == SkillPage.browserTab)
            OpenTab(
              path: path,
              workspace: workspace,
              until: _onPhone(until, skew).add(untilGrace),
            ),
      ];

/// [tabs] still open at [now].
List<OpenTab> stillOpen(List<OpenTab> tabs, DateTime now) => [
  for (final tab in tabs)
    if (tab.until.isAfter(now)) tab,
];

/// What browser-lean writes about a tab in `<token>.json`, beside its page: the page's [title]
/// and [host], whether the person holds it ([mine]), when its workspace's browser closes
/// ([until], on the phone's clock), and whether it is [closed].
class TabState {
  const TabState({
    this.title,
    this.host,
    this.mine = false,
    this.until,
    this.closed = false,
  });

  final String? title;
  final String? host;
  final bool mine;
  final DateTime? until;
  final bool closed;

  /// The state [json] holds, read with the server's clock [skew] ahead of the phone's, or null
  /// when it is not a tab's state. With no skew known, [until] has [untilGrace] added.
  static TabState? fromJson(Object? json, {Duration? skew}) {
    if (json is! Map) return null;
    if (json['closed'] == true) return const TabState(closed: true);
    final until = json['until'];
    return TabState(
      title: _text(json['title']),
      host: _text(json['host']),
      mine: json['who'] == 'user',
      until: until is int && until > 0
          ? _onPhone(until, skew).add(skew == null ? untilGrace : Duration.zero)
          : null,
    );
  }

  /// [value] trimmed, or null when it is not text or holds none.
  static String? _text(Object? value) => switch (value) {
    final String text when text.trim().isNotEmpty => text.trim(),
    _ => null,
  };

  /// Whether the tab is open at [now]: not [closed], and its [until] still to come.
  bool openAt(DateTime now) => !closed && (until?.isAfter(now) ?? true);
}

/// The path of the state browser-lean writes beside the tab's page at [path]: its
/// `<token>.json`.
String tabStatePath(String path) =>
    '${path.substring(0, path.length - '.html'.length)}.json';

/// A workspace's open tabs, each with its state when read, and when its browser [closes].
typedef TabGroup = ({
  String workspace,
  List<(OpenTab, TabState?)> tabs,
  DateTime closes,
});

/// The [listed] tabs open at [now], by workspace, the workspace whose browser closes soonest
/// first, each with its state as [stateOf] has it. A tab whose state says it closed, or past
/// its closing time, is left out.
List<TabGroup> tabGroups(
  List<OpenTab> listed,
  TabState? Function(String path) stateOf,
  DateTime now,
) {
  final bySlug = <String, List<(OpenTab, TabState?)>>{};
  for (final tab in stillOpen(listed, now)) {
    final state = stateOf(tab.path);
    if (state != null && !state.openAt(now)) continue;
    (bySlug[tab.workspace] ??= []).add((tab, state));
  }
  return [
    for (final MapEntry(key: workspace, value: tabs) in bySlug.entries)
      (
        workspace: workspace,
        tabs: tabs,
        closes: _earliest([
          for (final (tab, state) in tabs) state?.until ?? tab.until,
        ]),
      ),
  ]..sort((a, b) => a.closes.compareTo(b.closes));
}

DateTime _earliest(Iterable<DateTime> times) =>
    times.reduce((a, b) => a.isBefore(b) ? a : b);

/// How long until [until], from [now], in words: `closes in 3 min`, at least a minute, or in
/// hours from two hours on.
String closesIn(DateTime until, DateTime now) {
  final minutes = (until.difference(now).inSeconds / 60).ceil();
  if (minutes >= 120) return 'closes in ${(minutes / 60).round()} h';
  return 'closes in ${minutes < 1 ? 1 : minutes} min';
}

/// The Browser row's line for the [open] tabs at [now]: how many and when the first closes, or
/// `No tabs open`.
String browserLine(List<OpenTab> open, DateTime now) {
  if (open.isEmpty) return 'No tabs open';
  final first = closesIn(_earliest(open.map((tab) => tab.until)), now);
  final count = plural(open.length, 'tab', 'tabs');
  return open.length == 1
      ? '$count open · $first'
      : '$count open · first $first';
}
