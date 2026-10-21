import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/shortcuts.dart';
import 'package:anywherellm/ui/state/prefs_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_settings.dart';

const _s = 'https://s:3001';
const _use = ShortcutUse(label: 'Translate', detail: 'French');

/// A [PrefsController] over [store], loaded and on server [_s].
Future<PrefsController> _loaded(FakePrefsStore store) async {
  final prefs = PrefsController(store);
  await prefs.load();
  await prefs.useServer(_s);
  return prefs;
}

/// A store that counts its saves.
class _CountingStore extends FakePrefsStore {
  _CountingStore([super.saved]);

  int saves = 0;

  @override
  Future<void> save(Prefs prefs) async {
    saves++;
    await super.save(prefs);
  }
}

void main() {
  test(
    'renaming a workspace whose only data is shortcut uses moves them',
    () async {
      final store = FakePrefsStore(
        Prefs(
          shortcutUses: {Prefs.shortcutUseKey(_s, 'q3', 'budget', 42): _use},
        ),
      );
      final prefs = await _loaded(store);
      await prefs.renameWorkspace('q3', 'q4');
      expect(store.saved.shortcutUses.keys, [
        Prefs.shortcutUseKey(_s, 'q4', 'budget', 42),
      ]);
      expect(prefs.shortcutUse('q4', 'budget', 42)?.label, 'Translate');
    },
  );

  test(
    'renaming or forgetting a workspace nothing is kept of writes nothing',
    () async {
      final store = _CountingStore(const Prefs(workspaceOrder: ['household']));
      final prefs = await _loaded(store);
      await prefs.renameWorkspace('q3', 'q4');
      await prefs.forgetWorkspace('q3');
      expect(store.saves, 0);
      await prefs.forgetWorkspace('household');
      expect(store.saves, 1);
      expect(store.saved.workspaceOrder, isEmpty);
    },
  );
}
