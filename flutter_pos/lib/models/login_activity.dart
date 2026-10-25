class LoginActivity {
  final String id;
  final String userId;
  final String username;
  final String name;
  final String role;
  final String type; // 'login' or 'logout'
  final String at;
  String? photoPath;
  bool isSynced;

  static List<LoginActivity> openBaristaShifts(
      Iterable<LoginActivity> records) {
    final events = records
        .where((entry) =>
            entry.role.trim().toLowerCase() == 'barista' &&
            entry.userId.isNotEmpty &&
            (entry.type == 'login' || entry.type == 'logout'))
        .toList()
      ..sort((a, b) {
        final first = DateTime.tryParse(a.at);
        final second = DateTime.tryParse(b.at);
        return first != null && second != null
            ? first.compareTo(second)
            : a.at.compareTo(b.at);
      });

    final openByUser = <String, LoginActivity>{};
    for (final event in events) {
      if (event.type == 'login') {
        openByUser[event.userId] = event;
      } else {
        openByUser.remove(event.userId);
      }
    }

    return openByUser.values.toList()..sort((a, b) => b.at.compareTo(a.at));
  }

  static List<LoginActivity> openStaffShifts(Iterable<LoginActivity> records) {
    final events = records
        .where((entry) =>
            const {'barista', 'pos_cashier'}
                .contains(entry.role.trim().toLowerCase()) &&
            entry.userId.isNotEmpty &&
            (entry.type == 'login' || entry.type == 'logout'))
        .toList()
      ..sort((a, b) {
        final first = DateTime.tryParse(a.at);
        final second = DateTime.tryParse(b.at);
        return first != null && second != null
            ? first.compareTo(second)
            : a.at.compareTo(b.at);
      });

    final openByUser = <String, LoginActivity>{};
    for (final event in events) {
      if (event.type == 'login') {
        openByUser[event.userId] = event;
      } else {
        openByUser.remove(event.userId);
      }
    }
    return openByUser.values.toList()..sort((a, b) => b.at.compareTo(a.at));
  }

  LoginActivity({
    required this.id,
    required this.userId,
    required this.username,
    required this.name,
    required this.role,
    required this.type,
    required this.at,
    this.photoPath,
    this.isSynced = false,
  });

  factory LoginActivity.fromJson(Map<String, dynamic> json) {
    return LoginActivity(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? 'barista',
      type: json['type'] as String? ?? 'login',
      at: json['at'] as String? ?? DateTime.now().toIso8601String(),
      photoPath: json['photoPath'] as String? ?? json['photo_path'] as String?,
      isSynced: json['isSynced'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'username': username,
        'name': name,
        'role': role,
        'type': type,
        'at': at,
        'photoPath': photoPath,
        'isSynced': isSynced,
      };
}
