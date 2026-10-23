import 'package:anywherellm/core/browser_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

const _tab = '/browser-lean/aaaaaaaaaaaaaaaaaaaaaaaa.html';

DateTime _at(int minutes) => DateTime.utc(2026, 10, 23, 12, minutes);

int _ms(int minutes) => _at(minutes).millisecondsSinceEpoch;

OpenTab _open(int minutes, [String workspace = 'home']) =>
    OpenTab(path: _tab, workspace: workspace, until: _at(minutes));

void main() {
  group('openTabsOf', () {
    test('reads each tab of the shape the bridge passes', () {
      final tabs = openTabsOf([
        {'path': _tab, 'workspace': 'home', 'until': _ms(10)},
      ])!;
      expect(tabs.single.path, _tab);
      expect(tabs.single.workspace, 'home');
      // A minute's grace, since the bridge relists it only when it moves a minute.
      expect(tabs.single.until, _at(11));
    });

    test('puts until on the phone\'s clock', () {
      final tabs = openTabsOf([
        {'path': _tab, 'workspace': 'home', 'until': _ms(10)},
      ], skew: const Duration(minutes: 2))!;
      expect(tabs.single.until, _at(9));
    });

    test('leaves out an entry of any other shape', () {
      expect(
        openTabsOf([
          {'path': '/vault-lean/aaa.html', 'workspace': 'home', 'until': 1},
          {'path': 'https://x.example$_tab', 'workspace': 'home', 'until': 1},
          {'path': _tab, 'workspace': 'a b', 'until': 1},
          {'path': _tab, 'workspace': 'home', 'until': 0},
          {'path': _tab, 'workspace': 'home', 'until': '1'},
          {'path': _tab, 'workspace': 'home'},
          'not a tab',
        ]),
        isEmpty,
      );
    });

    test(
      'is null when the bridge does not say, and empty when it says none',
      () {
        expect(openTabsOf(null), isNull);
        expect(openTabsOf({'path': _tab}), isNull);
        expect(openTabsOf(const []), isEmpty);
      },
    );
  });

  test('a tab is open until its until', () {
    final tab = _open(10);
    expect(stillOpen([tab], _at(9)), [tab]);
    expect(stillOpen([tab], _at(10)), isEmpty);
  });

  group('TabState', () {
    test('reads the page, who has the tab and its until', () {
      final state = TabState.fromJson({
        'title': 'Boiler',
        'host': 'heating.example.com',
        'who': 'user',
        'until': _ms(10),
      }, skew: Duration.zero)!;
      expect(state.title, 'Boiler');
      expect(state.host, 'heating.example.com');
      expect(state.mine, isTrue);
      expect(state.until, _at(10));
      final agent = TabState.fromJson({'who': 'agent', 'title': '  '})!;
      expect(agent.mine, isFalse);
      expect(agent.title, isNull);
    });

    test('a closed tab, or anything but a state, is not open', () {
      expect(TabState.fromJson({'closed': true})!.openAt(_at(0)), isFalse);
      expect(TabState.fromJson('<html>'), isNull);
    });

    test('is open until its until on the server\'s clock', () {
      final state = TabState.fromJson({
        'until': _ms(10),
      }, skew: const Duration(minutes: 2))!;
      // The phone's 12:07 is the server's 12:09.
      expect(state.openAt(_at(7)), isTrue);
      expect(state.openAt(_at(8)), isFalse);
    });

    test('with no Date from the server, the phone\'s clock gets a minute', () {
      final state = TabState.fromJson({'until': _ms(10)})!;
      expect(state.openAt(_at(10).add(const Duration(seconds: 59))), isTrue);
      expect(state.openAt(_at(11)), isFalse);
    });

    test('with no until, it is open until it says closed', () {
      expect(const TabState().openAt(_at(0)), isTrue);
    });
  });

  group('tabGroups', () {
    const other = '/browser-lean/bbbbbbbbbbbbbbbbbbbbbbbb.html';
    const shut = '/browser-lean/cccccccccccccccccccccccc.html';
    final listed = [
      OpenTab(path: _tab, workspace: 'home', until: _at(14)),
      OpenTab(path: other, workspace: 'reading', until: _at(3)),
      OpenTab(path: shut, workspace: 'home', until: _at(14)),
    ];
    final states = {
      _tab: TabState(until: _at(12)),
      shut: const TabState(closed: true),
    };

    test(
      'groups by workspace, soonest to close first, closed tabs left out',
      () {
        final groups = tabGroups(listed, (path) => states[path], _at(0));
        expect([for (final g in groups) g.workspace], ['reading', 'home']);
        expect([for (final (tab, _) in groups.last.tabs) tab.path], [_tab]);
        // A tab's own state is exact, where the list may lag.
        expect(groups.last.closes, _at(12));
        expect(groups.first.closes, _at(3));
      },
    );

    test('drops a workspace whose browser has closed', () {
      expect(
        [
          for (final g in tabGroups(listed, (path) => states[path], _at(5)))
            g.workspace,
        ],
        ['home'],
      );
    });
  });

  test('the state sits beside the page', () {
    expect(tabStatePath(_tab), '/browser-lean/aaaaaaaaaaaaaaaaaaaaaaaa.json');
  });

  group('the Browser line', () {
    test('says how many tabs and when the first closes', () {
      expect(
        browserLine([_open(14), _open(3, 'reading'), _open(14)], _at(0)),
        '3 tabs open · first closes in 3 min',
      );
      expect(browserLine([_open(14)], _at(0)), '1 tab open · closes in 14 min');
      expect(browserLine(const [], _at(0)), 'No tabs open');
    });

    test('rounds up to the minute, from one, and counts hours from two', () {
      expect(
        closesIn(_at(0).add(const Duration(seconds: 61)), _at(0)),
        'closes in 2 min',
      );
      expect(
        closesIn(_at(0), _at(0).add(const Duration(seconds: 30))),
        'closes in 1 min',
      );
      expect(
        closesIn(_at(0).add(const Duration(minutes: 150)), _at(0)),
        'closes in 3 h',
      );
    });
  });
}
