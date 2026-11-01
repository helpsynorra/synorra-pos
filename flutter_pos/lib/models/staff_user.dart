class StaffUser {
  final String id;
  final String username;
  final String email;
  final String password;
  final bool passwordChanged;
  final String name;
  final String? avatarPath;
  final String role; // 'admin', 'cashier' (Owner), 'pos_cashier', 'barista'
  final String title;
  final Map<String, dynamic> permissions;

  const StaffUser({
    required this.id,
    required this.username,
    this.email = '',
    required this.password,
    this.passwordChanged = false,
    required this.name,
    this.avatarPath,
    required this.role,
    this.title = '',
    this.permissions = const {},
  });

  bool get canUsePos => role == 'cashier';
  bool get canLoginToPos => canUsePos;
  bool get canAccessBaristaShift => role == 'barista';
  bool get canClockShift => role == 'barista' || role == 'pos_cashier';
  bool get requiresAttendanceImage => permissions['required_image'] == true;
  bool get isManager => role == 'admin' || role == 'manager';

  static String parseRole(String rawRole, String title, String username) {
    final combined =
        '${rawRole.toLowerCase()} ${title.toLowerCase()} ${username.toLowerCase()}';
    final explicitRole = rawRole.trim().toLowerCase();
    if (explicitRole == 'admin') return 'admin';
    if (explicitRole == 'manager') return 'manager';
    if (explicitRole == 'pos_cashier') return 'pos_cashier';
    if (explicitRole == 'cashier') return 'cashier';
    final roleAndTitle = '${rawRole.toLowerCase()} ${title.toLowerCase()}';
    if (roleAndTitle.contains('manager')) return 'manager';
    if (roleAndTitle.contains('admin')) return 'admin';
    if (roleAndTitle.contains('cashier') ||
        roleAndTitle.contains('owner') ||
        roleAndTitle.contains('sale in charge')) {
      return 'cashier';
    }
    if (explicitRole == 'barista') return 'barista';
    if (combined.contains('admin')) return 'admin';
    return 'barista';
  }

  factory StaffUser.fromJson(Map<String, dynamic> json) {
    final rawRole = (json['role'] as String? ?? 'barista').trim();
    final rawTitle = (json['title'] as String? ?? '').trim();
    final rawUsername = (json['username'] as String? ?? '').trim();
    final resolvedRole = parseRole(rawRole, rawTitle, rawUsername);

    return StaffUser(
      id: json['id'] as String? ?? '',
      username: rawUsername.toLowerCase(),
      email: (json['email'] as String? ?? '').trim().toLowerCase(),
      password: json['password'] as String? ?? '',
      passwordChanged:
          json['passwordChanged'] == true || json['password_changed'] == true,
      name: (json['name'] as String? ?? '').trim().isNotEmpty
          ? (json['name'] as String).trim()
          : rawUsername,
      avatarPath:
          (json['avatarPath'] as String? ?? json['avatar_path'] as String?)
              ?.trim(),
      role: resolvedRole,
      title: resolvedRole == 'admin'
          ? 'Admin'
          : resolvedRole == 'cashier'
              ? 'Owner'
              : resolvedRole == 'pos_cashier'
                  ? 'Cashier'
                  : (rawTitle.isNotEmpty ? rawTitle : 'Barista'),
      permissions: json['permissions'] is Map
          ? Map<String, dynamic>.from(json['permissions'] as Map)
          : const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'passwordChanged': passwordChanged,
        'name': name,
        if (avatarPath != null && avatarPath!.isNotEmpty)
          'avatarPath': avatarPath,
        'role': role,
        'title': title,
        'permissions': permissions,
      };
}
