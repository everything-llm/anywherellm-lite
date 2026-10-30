import 'package:anywherellm/core/prefs.dart';
import 'package:anywherellm/core/users.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerUser', () {
    test('reads the id, name and role GET users lists', () {
      final user = ServerUser.fromJson({
        'id': 2,
        'username': ' jane_smith ',
        'role': 'default',
      })!;
      expect((user.id, user.name, user.role), (2, 'jane_smith', 'default'));
      expect(user.roleLabel, 'Default');
      expect(ServerUser.fromJson({'id': '7'})?.name, 'User 7');
      expect(ServerUser.fromJson({'username': 'no id'}), isNull);
      expect(ServerUser.fromJson('nope'), isNull);
    });

    test(
      'an admin and a manager open every workspace, anyone else only theirs',
      () {
        const sam = ServerUser(id: 1, name: 'Sam', role: 'admin');
        const alex = ServerUser(id: 2, name: 'Alex', role: 'manager');
        const robin = ServerUser(id: 3, name: 'Robin', role: 'default');
        expect(sam.opens(const []), isTrue);
        expect(alex.opens(const []), isTrue);
        expect(robin.opens(const []), isFalse);
        expect(robin.opens(const [WorkspaceMember(id: 3)]), isTrue);
        expect(robin.opens(const [WorkspaceMember(id: 1)]), isFalse);
      },
    );

    test('is kept in prefs by server, and read back', () {
      const robin = ServerUser(id: 3, name: 'Robin', role: 'default');
      final prefs = const Prefs().withUser('https://h:3001', robin);
      final read = Prefs.decode(prefs.encode());
      expect(read.userOn('https://h:3001'), robin);
      expect(read.userOn('https://other:3001'), isNull);
      expect(const Prefs().encode(), isNot(contains('users')));
      expect(
        Prefs.decode('{"users":{"https://h":{"name":"No id"}}}').users,
        isEmpty,
      );
    });
  });

  group('WorkspaceMember', () {
    const robin = ServerUser(id: 3, name: 'Robin');

    test('is matched by its userId, or user_id', () {
      expect(
        WorkspaceMember.fromJson({'userId': 3, 'role': 'member'})!
            .isUser(robin),
        isTrue,
      );
      expect(WorkspaceMember.fromJson({'user_id': '3'})!.isUser(robin), isTrue);
      expect(
        WorkspaceMember.fromJson({'userId': 4, 'username': 'Robin'})!
            .isUser(robin),
        isFalse,
      );
    });

    test('with no id, is matched by its username', () {
      expect(
        WorkspaceMember.fromJson({'username': 'Robin', 'role': 'default'})!
            .isUser(robin),
        isTrue,
      );
      expect(WorkspaceMember.fromJson({'role': 'admin'}), isNull);
    });
  });
}
