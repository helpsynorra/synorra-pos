import 'package:flutter/material.dart';

/// Shared status color language for Synorra POS.
///
/// Every status surface (attendance, inventory, order status, notifications)
/// should pick a tone from here instead of hardcoding colors, so the same
/// meaning always looks the same across the product.
class PosStatusTone {
  /// Solid fill for tiles/buttons that carry the status as their main action.
  final Color solid;

  /// Soft tint for chips, callouts, and card backgrounds.
  final Color tint;

  /// Border for tinted surfaces.
  final Color border;

  /// Text/icon color on tinted or white surfaces.
  final Color ink;

  const PosStatusTone({
    required this.solid,
    required this.tint,
    required this.border,
    required this.ink,
  });
}

class PosStatusColors {
  const PosStatusColors._();

  /// Active, available, clocked in, completed.
  static const PosStatusTone active = PosStatusTone(
    solid: Color(0xFF16A34A),
    tint: Color(0xFFECFDF3),
    border: Color(0xFFBBF7D0),
    ink: Color(0xFF15803D),
  );

  /// Paused, pending, on break, needs attention.
  static const PosStatusTone waiting = PosStatusTone(
    solid: Color(0xFFD97706),
    tint: Color(0xFFFFFBEB),
    border: Color(0xFFFDE68A),
    ink: Color(0xFFB45309),
  );

  /// End of a cycle, clocked out, informational accent.
  static const PosStatusTone closed = PosStatusTone(
    solid: Color(0xFF7C3AED),
    tint: Color(0xFFF5F3FF),
    border: Color(0xFFDDD6FE),
    ink: Color(0xFF6D28D9),
  );

  /// Destructive, void, out of stock.
  static const PosStatusTone danger = PosStatusTone(
    solid: Color(0xFFDC2626),
    tint: Color(0xFFFEF2F2),
    border: Color(0xFFFECACA),
    ink: Color(0xFFB91C1C),
  );

  /// Neutral/informational callouts.
  static const PosStatusTone info = PosStatusTone(
    solid: Color(0xFF2563EB),
    tint: Color(0xFFEFF6FF),
    border: Color(0xFFBFDBFE),
    ink: Color(0xFF1D4ED8),
  );

  static const PosStatusTone neutral = PosStatusTone(
    solid: Color(0xFF6B7280),
    tint: Color(0xFFF3F4F6),
    border: Color(0xFFE5E7EB),
    ink: Color(0xFF4B5563),
  );

  /// Color for an attendance punch type ('login', 'logout', 'break_start',
  /// 'break_end').
  static PosStatusTone forAttendanceAction(String? type) {
    switch (type) {
      case 'break_start':
        return waiting;
      case 'break_end':
        return active;
      case 'logout':
        return closed;
      case 'login':
        return active;
      default:
        return neutral;
    }
  }
}
