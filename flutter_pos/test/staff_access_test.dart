import 'package:flutter_test/flutter_test.dart';
import 'package:synorra_pos/models/login_activity.dart';
import 'package:synorra_pos/models/staff_user.dart';

void main() {
  test('POS access is cashier-only and shift access is barista-only', () {
    const cashier = StaffUser(
      id: 'cashier-1',
      username: 'cashier',
      password: 'pass',
      name: 'Cashier',
      role: 'cashier',
    );
    const manager = StaffUser(
      id: 'manager-1',
      username: 'manager',
      password: 'pass',
      name: 'Manager',
      role: 'manager',
    );
    const barista = StaffUser(
      id: 'barista-1',
      username: 'barista',
      password: 'pass',
      name: 'Barista',
      role: 'barista',
    );

    expect(cashier.canUsePos, isTrue);
    expect(cashier.canLoginToPos, isTrue);
    expect(cashier.canAccessBaristaShift, isFalse);
    expect(manager.canUsePos, isFalse);
    expect(manager.canLoginToPos, isFalse);
    expect(manager.isManager, isTrue);
    expect(manager.canAccessBaristaShift, isFalse);
    expect(barista.canUsePos, isFalse);
    expect(barista.canLoginToPos, isFalse);
    expect(barista.canAccessBaristaShift, isTrue);
  });

  test('multiple baristas stay on shift independently until each clocks out',
      () {
    final active = LoginActivity.openBaristaShifts([
      LoginActivity(
        id: 'barista-a-in',
        userId: 'barista-a',
        username: 'a',
        name: 'Barista A',
        role: 'barista',
        type: 'login',
        at: '2026-09-30T01:00:00Z',
      ),
      LoginActivity(
        id: 'barista-b-in',
        userId: 'barista-b',
        username: 'b',
        name: 'Barista B',
        role: 'barista',
        type: 'login',
        at: '2026-09-30T02:00:00Z',
      ),
      LoginActivity(
        id: 'barista-a-out',
        userId: 'barista-a',
        username: 'a',
        name: 'Barista A',
        role: 'barista',
        type: 'logout',
        at: '2026-09-30T03:00:00Z',
      ),
      LoginActivity(
        id: 'cashier-in',
        userId: 'cashier-1',
        username: 'cashier',
        name: 'Cashier',
        role: 'cashier',
        type: 'login',
        at: '2026-09-30T04:00:00Z',
      ),
      LoginActivity(
        id: 'cashier-out',
        userId: 'cashier-1',
        username: 'cashier',
        name: 'Cashier',
        role: 'cashier',
        type: 'logout',
        at: '2026-09-30T05:00:00Z',
      ),
    ]);

    expect(active.map((shift) => shift.userId), ['barista-b']);
  });
}
