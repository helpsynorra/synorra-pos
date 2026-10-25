import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synorra_pos/models/menu_item.dart';
import 'package:synorra_pos/models/login_activity.dart';
import 'package:synorra_pos/models/order.dart';
import 'package:synorra_pos/models/staff_user.dart';
import 'package:synorra_pos/services/local_storage_service.dart';
import 'package:synorra_pos/services/supabase_service.dart';
import 'package:synorra_pos/services/sync_service.dart';
import 'package:synorra_pos/state/pos_controller.dart';

class _MockSupabaseService extends SupabaseService {
  Order? lastPushedOrder;
  List<Map<String, dynamic>>? lastDeductions;

  @override
  bool get isPosApiTokenExpired => false;

  @override
  bool get hasPosApiToken => true;

  @override
  Future<Map<String, dynamic>> pushOrderAtomic(
    Order order,
    List<Map<String, dynamic>> deductions, {
    String? managerUsername,
    String? managerPassword,
  }) async {
    lastPushedOrder = order;
    lastDeductions = deductions;
    return {
      'ok': true,
      'ticketNo': null,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Waste Order Handling', () {
    test('Order model recognizes waste order and serializes wasteReason', () {
      final order = Order(
        id: 'waste-12345',
        createdAt: '2026-10-25T00:00:00Z',
        baristaName: 'Barista',
        items: [],
        subtotal: 0,
        total: 0,
        paymentMethod: 'waste',
        ticketNo: '',
        paid: 0,
        wasteReason: 'Wrong Preparation',
      );

      expect(order.isWaste, isTrue);
      expect(order.ticketNo, isEmpty);
      expect(order.wasteReason, 'Wrong Preparation');

      final json = order.toJson();
      expect(json['wasteReason'], 'Wrong Preparation');
      expect(json['paymentMethod'], 'waste');

      final reconstructed = Order.fromJson(json);
      expect(reconstructed.isWaste, isTrue);
      expect(reconstructed.wasteReason, 'Wrong Preparation');
    });

    test('recordWasteOrder requires non-empty reason and sets empty ticketNo',
        () async {
      SharedPreferences.setMockInitialValues({});
      final storage = LocalStorageService();
      await storage.init();
      final supabase = _MockSupabaseService();
      final sync =
          SyncService(supabaseService: supabase, localStorage: storage);
      final controller = PosController(
        localStorage: storage,
        supabaseService: supabase,
        syncService: sync,
      );
      const cashier = StaffUser(
        id: 'pos-cashier-1',
        username: 'sam',
        password: '',
        name: 'Sam Cashier',
        role: 'pos_cashier',
        title: 'Cashier',
      );
      controller.staffUsers.add(cashier);
      controller.shiftLogs.add(
        LoginActivity(
          id: 'shift-login-1',
          userId: cashier.id,
          username: cashier.username,
          name: cashier.name,
          role: cashier.role,
          type: 'login',
          at: DateTime.now().toIso8601String(),
        ),
      );

      final coffeeItem = const MenuItem(
        id: 'drink-1',
        name: 'Americano',
        price: 100,
        category: 'Drinks',
        image: '',
        available: true,
      );
      controller.addToCart(coffeeItem);

      // Attempting to record waste with empty reason must fail
      final emptyResult = await controller.recordWasteOrder(reason: '   ');
      expect(emptyResult['ok'], isFalse);
      expect(emptyResult['error'], contains('reason'));

      // Recording waste with a valid reason succeeds
      final successResult =
          await controller.recordWasteOrder(reason: 'Spilled');
      expect(successResult['ok'], isTrue);

      final recordedOrder = successResult['order'] as Order;
      expect(recordedOrder.isWaste, isTrue);
      expect(recordedOrder.wasteReason, 'Spilled');
      expect(recordedOrder.ticketNo, isEmpty);
      expect(recordedOrder.total, 0);
      expect(recordedOrder.baristaName, cashier.name);
      expect(recordedOrder.baristaUserId, cashier.id);
      expect(controller.lastCompletedOrder, isNull);

      // Pushed order to backend has empty ticketNo and wasteReason
      expect(supabase.lastPushedOrder?.ticketNo, isEmpty);
      expect(supabase.lastPushedOrder?.wasteReason, 'Spilled');
    });

    test(
        'nextTicketNoForOrders fills waste-created gaps before issuing new tickets',
        () {
      final now = DateTime(2026, 10, 25, 11, 38);
      final orders = [
        Order(
          id: 'ord-1',
          createdAt: '2026-10-25T11:36:00+08:00',
          baristaName: 'Cashier',
          items: [],
          subtotal: 0,
          total: 0,
          paymentMethod: 'cash',
          ticketNo: '#001',
          paid: 0,
        ),
        Order(
          id: 'waste-1',
          createdAt: '2026-10-25T11:37:00+08:00',
          baristaName: 'Cashier',
          items: [],
          subtotal: 0,
          total: 0,
          paymentMethod: 'waste',
          ticketNo: '#002',
          paid: 0,
          wasteReason: 'Spilled',
        ),
        Order(
          id: 'ord-2',
          createdAt: '2026-10-25T11:37:00+08:00',
          baristaName: 'Cashier',
          items: [],
          subtotal: 0,
          total: 0,
          paymentMethod: 'cash',
          ticketNo: '#003',
          paid: 0,
        ),
        Order(
          id: 'ord-3',
          createdAt: '2026-10-25T11:38:00+08:00',
          baristaName: 'Cashier',
          items: [],
          subtotal: 0,
          total: 0,
          paymentMethod: 'cash',
          ticketNo: '#004',
          paid: 0,
          voided: true,
        ),
      ];

      expect(nextTicketNoForOrders(orders, now), '#002');
    });
  });
}
