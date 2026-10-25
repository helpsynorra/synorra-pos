import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synorra_pos/models/menu_item.dart';
import 'package:synorra_pos/models/inventory_item.dart';
import 'package:synorra_pos/models/order.dart';
import 'package:synorra_pos/models/order_item.dart';
import 'package:synorra_pos/models/staff_user.dart';
import 'package:synorra_pos/manila_time.dart';
import 'package:synorra_pos/services/local_storage_service.dart';
import 'package:synorra_pos/services/offline_credential_store.dart';
import 'package:synorra_pos/services/supabase_service.dart';
import 'package:synorra_pos/services/sync_service.dart';
import 'package:synorra_pos/state/pos_controller.dart';
import 'package:synorra_pos/ui/widgets/cart_panel.dart';

class _RetryableFailureSupabaseService extends SupabaseService {
  @override
  bool get isPosApiTokenExpired => false;

  @override
  Future<Map<String, dynamic>> pushOrderAtomic(
    Order order,
    List<Map<String, dynamic>> deductions, {
    String? managerUsername,
    String? managerPassword,
  }) async {
    return {
      'ok': false,
      'error': 'Connection timed out',
      'retryable': true,
    };
  }
}

class _TimestampCaptureSupabaseService extends SupabaseService {
  final pushedCreatedAt = <String>[];
  final pushedOrders = <Order>[];

  @override
  bool get isPosApiTokenExpired => false;

  @override
  Future<Map<String, dynamic>> pushOrderAtomic(
    Order order,
    List<Map<String, dynamic>> deductions, {
    String? managerUsername,
    String? managerPassword,
  }) async {
    pushedCreatedAt.add(order.createdAt);
    pushedOrders.add(order);
    return {'ok': true, 'ticketNo': order.ticketNo};
  }

  @override
  Future<Map<String, dynamic>?> fetchFullStore() async => null;
}

class _RefreshingSessionSupabaseService
    extends _TimestampCaptureSupabaseService {
  final StaffUser staff;
  final authStarted = Completer<void>();
  final allowAuthentication = Completer<void>();
  int authCalls = 0;

  _RefreshingSessionSupabaseService(this.staff);

  @override
  Future<Map<String, dynamic>> authenticateStaff(
    String username,
    String password, {
    String email = '',
    bool persistSessionToken = true,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    authCalls++;
    if (!authStarted.isCompleted) authStarted.complete();
    await allowAuthentication.future;
    return {
      'ok': true,
      'user': staff,
      'token': 'fresh-pos-token',
    };
  }
}

class _MemoryOfflineCredentialStore implements OfflineCredentialStore {
  final credentials = <String, String>{};

  @override
  Future<void> save({required String staffId, required String password}) async {
    credentials[staffId] = password;
  }

  @override
  Future<String?> read({required String staffId}) async => credentials[staffId];

  @override
  Future<void> remove({required String staffId}) async {
    credentials.remove(staffId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restores checkout draft and clears it only when requested', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorageService();
    await storage.init();

    final item = OrderItem(
      productId: 'latte',
      name: 'Spanish Latte',
      qty: 2,
      price: 125,
      style: 'iced',
    );
    await storage.saveActiveCheckout(
      items: [item],
      paymentMethod: 'cash',
      tenderedAmount: 300,
      discountAmount: 0,
      pendingVoidRequestId: 'void-request-1',
    );

    final restored = storage.getActiveCheckout();
    expect(restored, isNotNull);
    expect(restored!['paymentMethod'], 'cash');
    expect(restored['tenderedAmount'], 300);
    expect(restored['pendingVoidRequestId'], 'void-request-1');
    final restoredItem = OrderItem.fromJson(
      Map<String, dynamic>.from((restored['items'] as List).first as Map),
    );
    expect(restoredItem.name, 'Spanish Latte');
    expect(restoredItem.qty, 2);
    expect(restoredItem.style, 'iced');

    await storage.clearActiveCheckout();
    expect(storage.getActiveCheckout(), isNull);
  });

  test('blocks adding menu items while a void request is pending', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorageService();
    await storage.init();
    final api = SupabaseService();
    final sync = SyncService(localStorage: storage, supabaseService: api);
    final controller = PosController(
      localStorage: storage,
      supabaseService: api,
      syncService: sync,
    )..pendingCartVoidRequestId = 'void-request-1';

    controller.addToCart(const MenuItem(
      id: 'latte',
      name: 'Latte',
      price: 125,
      category: 'Coffee',
      image: '',
    ));

    expect(controller.cart, isEmpty);
    controller.dispose();
    sync.dispose();
  });

  test('cash tender follows add-on total without replacing custom tender',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorageService();
    await storage.init();
    final api = SupabaseService();
    final sync = SyncService(localStorage: storage, supabaseService: api);
    final controller = PosController(
      localStorage: storage,
      supabaseService: api,
      syncService: sync,
    );
    const drink = MenuItem(
      id: 'americano',
      name: 'Americano',
      price: 120,
      category: 'Coffee',
      image: '',
    );
    const addon = OrderAddonSelection(id: 'oat', name: 'Oat', price: 40);

    controller.addToCart(drink, addons: const [addon]);
    expect(controller.total, 160);
    expect(controller.tenderedAmount, 160);

    controller.setTenderedAmount(500);
    controller.addToCart(drink, addons: const [addon]);
    expect(controller.total, 320);
    expect(controller.tenderedAmount, 500);

    controller.dispose();
    sync.dispose();
  });

  test('restores zero cash tender to the addon-inclusive checkout total',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorageService();
    await storage.init();
    await storage.saveActiveCheckout(
      items: [
        OrderItem(
          productId: 'americano',
          name: 'Americano',
          price: 120,
          addons: [
            const OrderAddonSelection(id: 'oat', name: 'Oat', price: 40),
          ],
        ),
      ],
      paymentMethod: 'cash',
      tenderedAmount: 0,
      discountAmount: 0,
    );
    final api = SupabaseService();
    final sync = SyncService(localStorage: storage, supabaseService: api);
    final controller = PosController(
      localStorage: storage,
      supabaseService: api,
      syncService: sync,
    );

    await controller.init();

    expect(controller.total, 160);
    expect(controller.tenderedAmount, 160);
    controller.dispose();
    sync.dispose();
  });

  test('queues an order when network fails before connectivity updates',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorageService();
    await storage.init();
    final api = _RetryableFailureSupabaseService()
      ..setPosApiToken('cached-pos-token');
    final sync = SyncService(localStorage: storage, supabaseService: api);
    final controller = PosController(
      localStorage: storage,
      supabaseService: api,
      syncService: sync,
    );
    controller.addToCart(const MenuItem(
      id: 'latte',
      name: 'Latte',
      price: 125,
      category: 'Coffee',
      image: '',
    ));
    final result = await controller.proceedOrder();

    expect(result['ok'], true);
    expect(result['synced'], false);
    expect(result['networkFailure'], true);
    expect(storage.getPendingOrders(), hasLength(1));
    expect(storage.getPendingOrders().single.items.single.name, 'Latte');

    controller.dispose();
    sync.dispose();
  });

  test('preserves device order time when an offline order syncs later',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorageService();
    await storage.init();
    final api = _TimestampCaptureSupabaseService()
      ..setPosApiToken('cached-pos-token');
    final sync = SyncService(localStorage: storage, supabaseService: api)
      ..isOnline = false;
    final controller = PosController(
      localStorage: storage,
      supabaseService: api,
      syncService: sync,
    );
    const rayhan = StaffUser(
      id: 'cashier-rayhan',
      username: 'rayhan',
      password: '',
      name: 'Rayhan',
      role: 'cashier',
    );
    const rey = StaffUser(
      id: 'cashier-rey',
      username: 'rey',
      password: '',
      name: 'Rey',
      role: 'cashier',
    );
    controller.currentUser = rayhan;

    controller.addToCart(const MenuItem(
      id: 'latte',
      name: 'Latte',
      price: 125,
      category: 'Coffee',
      image: '',
    ));
    final beforeCheckout = ManilaTime.now();
    final result = await controller.proceedOrder();
    final afterCheckout = ManilaTime.now();

    expect(result['ok'], true);
    final queuedOrder = storage.getPendingOrders().single;
    expect(queuedOrder.baristaName, rayhan.name);
    expect(queuedOrder.baristaUserId, rayhan.id);
    final createdAt = ManilaTime.parse(queuedOrder.createdAt);
    expect(createdAt, isNotNull);
    expect(createdAt!.isBefore(beforeCheckout), isFalse);
    expect(createdAt.isAfter(afterCheckout), isFalse);

    sync.isOnline = true;
    controller.currentUser = rey;
    await sync.syncAll();

    expect(api.pushedCreatedAt, [queuedOrder.createdAt]);
    expect(api.pushedOrders.single.baristaName, rayhan.name);
    expect(api.pushedOrders.single.baristaUserId, rayhan.id);
    expect(storage.getPendingOrders(), isEmpty);

    controller.dispose();
    sync.dispose();
  });

  test('refreshes the POS session before placing an online order', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorageService(
      offlineCredentialStore: _MemoryOfflineCredentialStore(),
    );
    await storage.init();
    const staff = StaffUser(
      id: 'cashier-1',
      username: 'rey',
      password: '',
      name: 'Rey',
      role: 'cashier',
    );
    await storage.saveActiveStaffSession(staff);
    await storage.saveOfflineStaffCredential(staff.id, '1234');
    final api = _RefreshingSessionSupabaseService(staff);
    final sync = SyncService(localStorage: storage, supabaseService: api)
      ..isOnline = true;
    final controller = PosController(
      localStorage: storage,
      supabaseService: api,
      syncService: sync,
    );
    controller.addToCart(const MenuItem(
      id: 'latte',
      name: 'Latte',
      price: 125,
      category: 'Coffee',
      image: '',
    ));

    final backgroundRefresh = sync.ensurePosApiToken();
    await api.authStarted.future;
    final checkout = controller.proceedOrder();
    api.allowAuthentication.complete();
    final result = await checkout;
    await backgroundRefresh;

    expect(api.authCalls, 1);
    expect(result['synced'], true);
    expect(storage.getPendingOrders(), isEmpty);

    await sync.syncAll();
    controller.dispose();
    sync.dispose();
  });

  test('finds insufficient recipe and cup stock for the full cart', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorageService();
    await storage.init();
    await storage.saveInventory([
      InventoryItem(id: 'milk', name: 'Milk', stock: 0.2, unit: 'L'),
      InventoryItem(id: 'hot-cup', name: 'Hot Cup', stock: 1, unit: 'pcs'),
    ]);
    await storage.saveRecipesData({
      'recipeCostings': [
        {
          'menuItems': ['Latte'],
          'ingredients': [
            {
              'inventoryItemId': 'milk',
              'name': 'Milk',
              'amount': 0.2,
              'unit': 'L'
            },
          ],
          'hotCupInventoryItemId': 'hot-cup',
        },
      ],
    });
    final api = SupabaseService();
    final sync = SyncService(localStorage: storage, supabaseService: api);

    final shortages = sync.findStockShortfalls([
      OrderItem(
        productId: 'latte',
        name: 'Latte',
        qty: 2,
        price: 120,
        style: 'hot',
      ),
    ]);

    expect(shortages.map((item) => item['itemName']),
        containsAll(['Milk', 'Hot Cup']));
    expect(
      shortages.firstWhere((item) => item['itemName'] == 'Milk')['required'],
      0.4,
    );
    expect(
      shortages.firstWhere((item) => item['itemName'] == 'Hot Cup')['required'],
      2,
    );

    sync.dispose();
  });

  testWidgets('checkout fits when the keyboard reduces panel height',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorageService();
    await storage.init();
    final api = SupabaseService();
    final sync = SyncService(localStorage: storage, supabaseService: api);
    final controller = PosController(
      localStorage: storage,
      supabaseService: api,
      syncService: sync,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 250),
            viewInsets: EdgeInsets.only(bottom: 250),
          ),
          child: SizedBox(
            height: 250,
            child: Material(
              child: CartPanel(
                controller: controller,
                isFullWidth: true,
                isKeyboardOpen: true,
                onProceedOrder: () {},
                onRecordWaste: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('Proceed Order'), findsOneWidget);
    expect(find.text('Print'), findsNothing);

    var controllerNotifications = 0;
    controller.addListener(() => controllerNotifications++);

    // The Amount field is read-only; tapping it opens the external numeric keypad.
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '1'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '2'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '3'));
    await tester.pump();

    expect(controller.tenderedAmount, 123);
    expect(controllerNotifications, 0);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    sync.dispose();
  });
}
