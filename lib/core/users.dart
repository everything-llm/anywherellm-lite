// The people of a multi-user AnythingLLM server, as its developer API lists them. The key opens
// the whole server whoever they are; the one this device's chats are saved as is chosen on the
// Connection page, and is not a sign-in.

import 'json.dart';

/// Someone with an account on a multi-user server, as `GET /v1/users` lists them: their [id],
/// which the chat calls take as `userId`, their [name] and their [role].
class ServerUser {
  const ServerUser({required this.id, required this.name, this.role = ''});

  /// An entry of `users`, or null when it has no whole-number `id`.
  static ServerUser? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _id(json['id']);
    if (id == null) return null;
    return ServerUser(
      id: id,
      name: _trimmed(json['username']) ?? 'User $id',
      role: _trimmed(json['role']) ?? '',
    );
  }

  final int id;
  final String name;

  /// The server's own word for it: `admin`, `manager` or `default`, or empty when it gave none.
  final String role;

  /// The role as the Connection page shows it: Admin, Manager or Default.
  String get roleLabel =>
      role.isEmpty ? '' : '${role[0].toUpperCase()}${role.substring(1)}';

  /// Whether they open every workspace, as an admin and a manager do, whoever the workspace
  /// lists.
  bool get opensEvery => role == 'admin' || role == 'manager';

  /// Whether they open a workspace whose users are [members].
  bool opens(List<WorkspaceMember> members) =>
      opensEvery || members.any((m) => m.isUser(this));

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'role': role};

  /// Reads what [toJson] wrote, or null when it cannot.
  static ServerUser? fromSaved(Object? json) {
    if (json is! Map) return null;
    final id = _id(json['id']);
    final name = textOrNull(json['name']);
    if (id == null || name == null) return null;
    return ServerUser(id: id, name: name, role: textOrNull(json['role']) ?? '');
  }

  @override
  bool operator ==(Object other) =>
      other is ServerUser &&
      other.id == id &&
      other.name == name &&
      other.role == role;

  @override
  int get hashCode => Object.hash(id, name, role);
}

/// One of the users a workspace lists, as `GET /v1/admin/workspaces/{id}/users` answers: by
/// [id] where the answer carries one, as `userId` or `user_id`, or else by [name].
class WorkspaceMember {
  const WorkspaceMember({this.id, this.name});

  /// An entry of `users`, or null when it names no one.
  static WorkspaceMember? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _id(json['userId'] ?? json['user_id']);
    final name = _trimmed(json['username']);
    if (id == null && name == null) return null;
    return WorkspaceMember(id: id, name: name);
  }

  final int? id;
  final String? name;

  /// Whether this is [user]: by id when the server gave one, else by name.
  bool isUser(ServerUser user) =>
      id != null ? id == user.id : name == user.name;
}

/// [value] as a whole number when it is one or a number as text, or else null.
int? _id(Object? value) => switch (value) {
  final int n => n,
  final String s => int.tryParse(s.trim()),
  _ => null,
};

/// [value] trimmed when it is text that is not empty, or else null.
String? _trimmed(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
