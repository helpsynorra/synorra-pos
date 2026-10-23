class StaffUser {
  final String id;
  final String username;
  final String email;
  final String password;
  final bool passwordChanged;
  final String name;
  final String role; // 'admin', 'cashier' (Owner), 'pos_cashier', 'barista'
  final String title;

  const StaffUser({
    required this.id,
    required this.username,
    this.email = '',
    required this.password,
    this.passwordChanged = false,
    required this.name,
    required this.role,
    this.title = '',
  });

  bool get canUsePos => role == 'cashier';
  bool get canLoginToPos => canUsePos;
  bool get canAccessBaristaShift => role == 'barista';
  bool get canClockShift => role == 'barista' || role == 'pos_cashier';
  bool get isManager => role == 'admin';

  static String parseRole(String rawRole, String title, String username) {
    final combined =
        '${rawRole.toLowerCase()} ${title.toLowerCase()} ${username.toLowerCase()}';
    final explicitRole = rawRole.trim().toLowerCase();
    if (explicitRole == 'admin') return 'admin';
    if (explicitRole == 'pos_cashier') return 'pos_cashier';
    if (explicitRole == 'cashier') return 'cashier';
    final roleAndTitle = '${rawRole.toLowerCase()} ${title.toLowerCase()}';
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
      passwordChanged: json['passwordChanged'] == true || json['password_changed'] == true,
      name: (json['name'] as String? ?? '').trim().isNotEmpty
          ? (json['name'] as String).trim()
          : rawUsername,
      role: resolvedRole,
      title: resolvedRole == 'admin'
          ? 'Admin'
          : resolvedRole == 'cashier'
              ? 'Owner'
              : resolvedRole == 'pos_cashier'
                  ? 'Cashier'
              : (rawTitle.isNotEmpty ? rawTitle : 'Barista'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'passwordChanged': passwordChanged,
        'name': name,
        'role': role,
        'title': title,
      };
}
