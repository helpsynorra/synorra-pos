import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synorra_pos/models/staff_user.dart';
import 'package:synorra_pos/ui/widgets/barista_shift_dialog.dart';

const StaffUser ana = StaffUser(
  id: 'ana',
  username: 'ana',
  password: '',
  name: 'Ana Cruz',
  role: 'barista',
  title: 'Barista',
);

Widget wrap({
  required List<StaffUser> onShift,
  Set<String> onBreak = const <String>{},
  Map<String, String> since = const <String, String>{},
}) {
  return MaterialApp(
    home: Scaffold(
      body: BaristaShiftDialog(
        onShiftBaristas: onShift,
        onBreakStaffIds: onBreak,
        onShiftSince: since,
        staffUsers: const [ana],
        authMode: 'username_password',
        authenticateBarista: (_, __) async => null,
        resolveStaffAvatarUrl: (_) async => null,
        onPunch: (_, __,
            {required username, required password, photoBytes}) async {},
      ),
    ),
  );
}

void main() {
  testWidgets('clocked out staff only see the clock-in action', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(onShift: const []));
    await tester.pumpAndSettle();

    expect(find.text('Clock In'), findsOneWidget);
    expect(find.text('Break Time'), findsNothing);
    expect(find.text('Clock Out'), findsNothing);
    expect(find.textContaining('No one is clocked in yet'), findsOneWidget);
  });

  testWidgets('on-shift staff get break and clock-out actions', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(
      onShift: const [ana],
      since: const {'ana': '2026-10-30T01:04:00.000Z'},
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Since 9:04 AM'), findsOneWidget);
    expect(find.text('On shift'), findsOneWidget);

    await tester.tap(find.text('Ana Cruz'));
    await tester.pumpAndSettle();

    expect(find.text('Break Time'), findsOneWidget);
    expect(find.text('Clock Out'), findsOneWidget);
    expect(find.text('Resume Shift'), findsNothing);

    await tester.tap(find.text('Break Time'));
    await tester.pumpAndSettle();

    expect(find.text('Start break'), findsWidgets);
    expect(find.text('Verify identity'), findsOneWidget);
  });

  testWidgets('on-break staff can resume instead of starting a break',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(
      onShift: const [ana],
      onBreak: const {'ana'},
      since: const {'ana': '2026-10-30T01:04:00.000Z'},
    ));
    await tester.pumpAndSettle();

    expect(find.text('On break'), findsOneWidget);

    await tester.tap(find.text('Ana Cruz'));
    await tester.pumpAndSettle();

    expect(find.text('Resume Shift'), findsOneWidget);
    expect(find.text('Clock Out'), findsOneWidget);
    expect(find.text('Break Time'), findsNothing);
  });

  testWidgets('clock-in form starts with no role selected', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(onShift: const []));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clock In'));
    await tester.pumpAndSettle();

    expect(find.text('Cashier'), findsOneWidget);
    expect(find.text('Barista'), findsWidgets);
    expect(find.text('New shift'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Clock in'));
    await tester.pumpAndSettle();

    expect(find.text('Choose the staff role to continue.'), findsOneWidget);
  });
}
