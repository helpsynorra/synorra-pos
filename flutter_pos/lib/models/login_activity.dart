class StaffShiftState {
  final String userId;
  final String startedAt;
  String? breakStartedAt;

  StaffShiftState({
    required this.userId,
    required this.startedAt,
    this.breakStartedAt,
  });

  bool get onBreak => breakStartedAt != null;
}

class LoginActivity {
  static const String loginType = 'login';
  static const String logoutType = 'logout';
  static const String breakStartType = 'break_start';
  static const String breakEndType = 'break_end';

  final String id;
  final String userId;
  final String username;
  final String name;
  final String role;
  final String type; // 'login' | 'logout' | 'break_start' | 'break_end'
  final String at;
  String? photoPath;
  bool isSynced;

  static bool isBreakType(String type) =>
      type == breakStartType || type == breakEndType;

  static bool isAttendanceType(String type) =>
      type == loginType || type == logoutType || isBreakType(type);

  static List<LoginActivity> _chronological(Iterable<LoginActivity> records) {
    return records
        .where((entry) =>
            const {'barista', 'pos_cashier'}
                .contains(entry.role.trim().toLowerCase()) &&
            entry.userId.isNotEmpty &&
            isAttendanceType(entry.type))
        .toList()
      ..sort((a, b) {
        final first = DateTime.tryParse(a.at);
        final second = DateTime.tryParse(b.at);
        return first != null && second != null
            ? first.compareTo(second)
            : a.at.compareTo(b.at);
      });
  }

  static List<LoginActivity> openBaristaShifts(
      Iterable<LoginActivity> records) {
    final events = _chronological(records)
        .where((entry) => entry.role.trim().toLowerCase() == 'barista')
        .toList();

    final openByUser = <String, LoginActivity>{};
    for (final event in events) {
      if (event.type == loginType) {
        openByUser[event.userId] = event;
      } else if (event.type == logoutType) {
        openByUser.remove(event.userId);
      }
    }

    return openByUser.values.toList()..sort((a, b) => b.at.compareTo(a.at));
  }

  static List<LoginActivity> openStaffShifts(Iterable<LoginActivity> records) {
    final events = _chronological(records);
    final openByUser = <String, LoginActivity>{};
    for (final event in events) {
      if (event.type == loginType) {
        openByUser[event.userId] = event;
      } else if (event.type == logoutType) {
        openByUser.remove(event.userId);
      }
    }
    return openByUser.values.toList()..sort((a, b) => b.at.compareTo(a.at));
  }

  /// Replays attendance events to expose who is clocked in, when their shift
  /// started, and who is currently on break. Break events sit inside an open
  /// shift, so they never remove the shift itself.
  static Map<String, StaffShiftState> openShiftStates(
      Iterable<LoginActivity> records) {
    final events = _chronological(records);
    final openByUser = <String, StaffShiftState>{};
    for (final event in events) {
      switch (event.type) {
        case loginType:
          openByUser[event.userId] = StaffShiftState(
            userId: event.userId,
            startedAt: event.at,
          );
          break;
        case logoutType:
          openByUser.remove(event.userId);
          break;
        case breakStartType:
          final state = openByUser[event.userId];
          if (state != null && !state.onBreak) {
            state.breakStartedAt = event.at;
          }
          break;
        case breakEndType:
          openByUser[event.userId]?.breakStartedAt = null;
          break;
      }
    }
    return openByUser;
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
