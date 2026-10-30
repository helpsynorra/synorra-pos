import 'package:flutter_test/flutter_test.dart';
import 'package:synorra_pos/models/login_activity.dart';

LoginActivity event(String id, String userId, String type, String at,
    {String role = 'barista'}) {
  return LoginActivity(
    id: id,
    userId: userId,
    username: userId,
    name: userId,
    role: role,
    type: type,
    at: at,
  );
}

void main() {
  group('LoginActivity.openShiftStates', () {
    test('tracks shift start and open breaks', () {
      final states = LoginActivity.openShiftStates([
        event('1', 'ana', 'login', '2026-10-30T01:00:00.000Z'),
        event('2', 'ben', 'login', '2026-10-30T01:30:00.000Z'),
        event('3', 'ana', 'break_start', '2026-10-30T02:00:00.000Z'),
        event('4', 'ben', 'break_start', '2026-10-30T02:05:00.000Z'),
        event('5', 'ben', 'break_end', '2026-10-30T02:20:00.000Z'),
      ]);

      expect(states.keys, containsAll(['ana', 'ben']));
      expect(states['ana']!.startedAt, '2026-10-30T01:00:00.000Z');
      expect(states['ana']!.onBreak, isTrue);
      expect(states['ana']!.breakStartedAt, '2026-10-30T02:00:00.000Z');
      expect(states['ben']!.startedAt, '2026-10-30T01:30:00.000Z');
      expect(states['ben']!.onBreak, isFalse);
      expect(states['ben']!.breakStartedAt, isNull);
    });

    test('break events never end the shift and logout clears break state', () {
      final states = LoginActivity.openShiftStates([
        event('1', 'ana', 'login', '2026-10-30T01:00:00.000Z'),
        event('2', 'ana', 'break_start', '2026-10-30T02:00:00.000Z'),
        event('3', 'ana', 'logout', '2026-10-30T03:00:00.000Z'),
      ]);

      expect(states, isEmpty);
    });

    test('ignores orphan break events and unsupported roles', () {
      final states = LoginActivity.openShiftStates([
        event('1', 'ana', 'break_start', '2026-10-30T02:00:00.000Z'),
        event('2', 'mgr', 'login', '2026-10-30T01:00:00.000Z', role: 'manager'),
      ]);

      expect(states, isEmpty);
    });

    test('isAttendanceType accepts exactly the four punch types', () {
      expect(LoginActivity.isAttendanceType('login'), isTrue);
      expect(LoginActivity.isAttendanceType('logout'), isTrue);
      expect(LoginActivity.isAttendanceType('break_start'), isTrue);
      expect(LoginActivity.isAttendanceType('break_end'), isTrue);
      expect(LoginActivity.isAttendanceType('void'), isFalse);
    });

    test('openStaffShifts still ignores break events', () {
      final open = LoginActivity.openStaffShifts([
        event('1', 'ana', 'login', '2026-10-30T01:00:00.000Z'),
        event('2', 'ana', 'break_start', '2026-10-30T02:00:00.000Z'),
      ]);

      expect(open.map((entry) => entry.userId), ['ana']);
    });
  });
}
