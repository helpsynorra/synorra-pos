import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:synorra_pos/models/order.dart';
import 'package:synorra_pos/models/order_item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synorra_pos/models/staff_user.dart';
import 'package:synorra_pos/services/local_storage_service.dart';
import 'package:synorra_pos/services/offline_credential_store.dart';
import 'package:synorra_pos/services/supabase_service.dart';
import 'package:synorra_pos/services/sync_service.dart';
import 'package:synorra_pos/state/pos_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('active account profile persists without its password until logout',
      () async {
    final storage = LocalStorageService();
    await storage.init();

    expect(storage.getActiveStaffId(), isNull);

    await storage.saveActiveStaffSession(
      const StaffUser(
        id: 'staff-123',
        username: 'ray',
        password: 'secret',
        name: 'Ray',
        role: 'cashier',
      ),
    );
    expect(storage.getActiveStaffId(), 'staff-123');
    expect(storage.getActiveStaffProfile()?.name, 'Ray');
    expect(storage.getActiveStaffProfile()?.password, isEmpty);

    await storage.clearActiveStaffId();
    expect(storage.getActiveStaffId(), isNull);
    expect(storage.getActiveStaffProfile(), isNull);
  });

  test('offline credentials use the secure credential store, not preferences',
      () async {
    final credentials = _MemoryOfflineCredentialStore();
    final storage = LocalStorageService(offlineCredentialStore: credentials);
    await storage.init();

    await storage.saveOfflineStaffCredential('staff-123', 'secret');

    expect(await storage.getOfflineStaffCredential('staff-123'), 'secret');
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('legacy cached staff passwords migrate to secure storage during init',
      () async {
    SharedPreferences.setMockInitialValues({
      'v2_cache_staff_users':
          '[{"id":"staff-123","username":"ray","password":"old-secret","name":"Ray","role":"cashier"}]',
    });
    final storage = LocalStorageService(
      offlineCredentialStore: _MemoryOfflineCredentialStore(),
    );
    await storage.init();

    expect(storage.getStaff().single.password, isEmpty);
    expect(
      (await SharedPreferences.getInstance()).getString('v2_cache_staff_users'),
      isNot(contains('old-secret')),
    );
    expect(await storage.getOfflineStaffCredential('staff-123'), 'old-secret');
  });

  test('barista and manager can authenticate offline only for their purposes',
      () async {
    final credentials = _MemoryOfflineCredentialStore();
    final storage = LocalStorageService(offlineCredentialStore: credentials);
    await storage.init();
    const manager = StaffUser(
      id: 'manager-1',
      username: 'manager',
      password: '',
      name: 'Manager',
      role: 'manager',
    );
    const barista = StaffUser(
      id: 'barista-1',
      username: 'barista',
      password: '',
      name: 'Barista',
      role: 'barista',
    );
    const cashier = StaffUser(
      id: 'cashier-1',
      username: 'cashier',
      password: '',
      name: 'Cashier',
      role: 'cashier',
    );
    await storage.saveStaff([manager, barista, cashier]);
    await storage.saveOfflineStaffCredential(manager.id, 'manager-pass');
    await storage.saveOfflineStaffCredential(barista.id, 'barista-pass');
    await storage.saveOfflineStaffCredential(cashier.id, 'cashier-pass');

    final api = _StubSupabaseService({'ok': false, 'offline': true});
    final sync = SyncService(localStorage: storage, supabaseService: api);
    final controller = PosController(
      localStorage: storage,
      supabaseService: api,
      syncService: sync,
    );

    expect(
      (await controller.authenticateStaffForPurpose(
        'manager',
        'manager-pass',
        accepts: (staff) => staff.isManager,
      ))
          ?.id,
      manager.id,
    );
    expect(
      (await controller.authenticateStaffForPurpose(
        'barista',
        'barista-pass',
        accepts: (staff) => staff.canAccessBaristaShift,
      ))
          ?.id,
      barista.id,
    );
    expect(
      await controller.authenticateStaffForPurpose(
        'cashier',
        'cashier-pass',
        accepts: (staff) => staff.isManager,
      ),
      isNull,
    );

    controller.dispose();
    sync.dispose();
  });

  test('successful online purpose auth saves secure offline credential',
      () async {
    final credentials = _MemoryOfflineCredentialStore();
    final storage = LocalStorageService(offlineCredentialStore: credentials);
    await storage.init();
    const barista = StaffUser(
      id: 'barista-1',
      username: 'barista',
      password: '',
      name: 'Barista',
      role: 'barista',
    );
    final api = _StubSupabaseService({'ok': true, 'user': barista});
    final sync = SyncService(localStorage: storage, supabaseService: api);
    final controller = PosController(
      localStorage: storage,
      supabaseService: api,
      syncService: sync,
    );

    expect(
      (await controller.authenticateStaffForPurpose(
        'barista',
        'barista-pass',
        accepts: (staff) => staff.canAccessBaristaShift,
      ))
          ?.id,
      barista.id,
    );
    expect(
      await storage.getOfflineStaffCredential(barista.id),
      'barista-pass',
    );
    expect(storage.getStaff().single.password, isEmpty);

    controller.dispose();
    sync.dispose();
  });

  test('cached staff password works when internet is unavailable', () async {
    final credentials = _MemoryOfflineCredentialStore();
    final storage = LocalStorageService(offlineCredentialStore: credentials);
    await storage.init();
    const staff = StaffUser(
      id: 'staff-1',
      username: 'rey',
      email: 'rey@example.com',
      password: '',
      name: 'Rey',
      role: 'cashier',
    );
    await storage.saveStaff([staff]);
    await storage.saveOfflineStaffCredential(staff.id, '1234');

    final api = _StubSupabaseService({'ok': false, 'offline': true});
    final sync = SyncService(localStorage: storage, supabaseService: api);
    final controller = PosController(
      localStorage: storage,
      supabaseService: api,
      syncService: sync,
    );

    sync.isOnline = true;
    expect(
      (await controller.authenticateCachedStaffOffline(
        email: 'rey@example.com',
        password: '1234',
      ))
          ?.id,
      staff.id,
    );

    await storage.saveOfflineStaffCredential(staff.id, 'different');
    expect(
      await controller.authenticateCachedStaffOffline(
        email: 'rey@example.com',
        password: '1234',
      ),
      isNull,
    );

    controller.dispose();
    sync.dispose();
  });

  test('offline manager void queues and replays with manager credentials',
      () async {
    final credentials = _MemoryOfflineCredentialStore();
    final storage = LocalStorageService(offlineCredentialStore: credentials);
    await storage.init();
    const manager = StaffUser(
      id: 'manager-1',
      username: 'manager',
      password: '',
      name: 'Manager',
      role: 'manager',
    );
    await storage.saveStaff([manager]);
    await storage.saveOfflineStaffCredential(manager.id, 'manager-pass');

    final api = _StubSupabaseService(
      {'ok': false, 'offline': true},
      orderResponse: {'ok': true, 'ticketNo': '#007'},
    );
    final sync = SyncService(localStorage: storage, supabaseService: api)
      ..isOnline = false;
    final controller = PosController(
      localStorage: storage,
      supabaseService: api,
      syncService: sync,
    );
    controller.cart.add(OrderItem(
      productId: 'drink-1',
      name: 'Cappuccino',
      price: 135,
    ));

    final voidResult = await controller.voidCheckout(
      'Duplicate order',
      'manager',
      'manager-pass',
    );

    expect(voidResult['ok'], isTrue);
    expect(voidResult['queued'], isTrue);
    expect(storage.getPendingOrders().single.voided, isTrue);
    expect(storage.getPendingOrders().single.voidedBy, manager.id);
    expect(api.pushedOrders, isEmpty);

    final expiry =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch /
            1000;
    final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': expiry})));
    api.setPosApiToken('$payload.signature');
    sync.isOnline = true;
    await sync.syncAll();

    expect(storage.getPendingOrders(), isEmpty);
    expect(api.pushedOrders, hasLength(1));
    expect(api.pushedManagerUsername, 'manager');
    expect(api.pushedManagerPassword, 'manager-pass');
    expect(api.pushedDeductions, isEmpty);

    controller.dispose();
    sync.dispose();
  });

  test('only cashiers can enter POS from cached accounts', () {
    expect(
      const StaffUser(
        id: 'cashier',
        username: 'cashier',
        password: '',
        name: 'Cashier',
        role: 'cashier',
      ).canLoginToPos,
      isTrue,
    );
    expect(
      const StaffUser(
        id: 'manager',
        username: 'manager',
        password: '',
        name: 'Manager',
        role: 'manager',
      ).canLoginToPos,
      isFalse,
    );
    expect(
      const StaffUser(
        id: 'barista',
        username: 'barista',
        password: '',
        name: 'Barista',
        role: 'barista',
      ).canLoginToPos,
      isFalse,
    );
    expect(
      const StaffUser(
        id: 'admin',
        username: 'admin',
        password: '',
        name: 'Admin',
        role: 'admin',
      ).canLoginToPos,
      isFalse,
    );
  });

  test('only barista shift activity is queued from POS session events',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = LocalStorageService();
    await storage.init();
    final api = SupabaseService();
    final sync = SyncService(localStorage: storage, supabaseService: api)
      ..isOnline = false;
    final controller = PosController(
      localStorage: storage,
      supabaseService: api,
      syncService: sync,
    );
    const manager = StaffUser(
      id: 'manager-1',
      username: 'manager',
      password: '',
      name: 'Manager',
      role: 'manager',
    );
    const barista = StaffUser(
      id: 'barista-1',
      username: 'barista',
      password: '',
      name: 'Barista',
      role: 'barista',
    );

    await controller.recordStaffSessionEvent(manager, 'login');
    await controller.recordStaffSessionEvent(barista, 'login');

    final pending = storage.getPendingLoginActivity();
    expect(pending.map((event) => event.role), ['barista']);
    expect(pending, hasLength(1));

    controller.dispose();
    sync.dispose();
  });
}

class _MemoryOfflineCredentialStore implements OfflineCredentialStore {
  final Map<String, String> _credentials = {};

  @override
  Future<void> save({required String staffId, required String password}) async {
    _credentials[staffId] = password;
  }

  @override
  Future<String?> read({required String staffId}) async =>
      _credentials[staffId];

  @override
  Future<void> remove({required String staffId}) async {
    _credentials.remove(staffId);
  }
}

class _StubSupabaseService extends SupabaseService {
  final Map<String, dynamic> authResponse;
  final Map<String, dynamic> orderResponse;
  final List<Order> pushedOrders = [];
  String? pushedManagerUsername;
  String? pushedManagerPassword;
  List<Map<String, dynamic>> pushedDeductions = [];

  _StubSupabaseService(
    this.authResponse, {
    this.orderResponse = const {'ok': false},
  });

  @override
  Future<Map<String, dynamic>> authenticateStaff(
    String username,
    String password, {
    String email = '',
    bool persistSessionToken = true,
    Duration timeout = const Duration(seconds: 12),
  }) async =>
      authResponse;

  @override
  Future<Map<String, dynamic>> pushOrderAtomic(
    Order order,
    List<Map<String, dynamic>> deductions, {
    String? managerUsername,
    String? managerPassword,
  }) async {
    pushedOrders.add(order);
    pushedManagerUsername = managerUsername;
    pushedManagerPassword = managerPassword;
    pushedDeductions = deductions;
    return orderResponse;
  }

  @override
  Future<Map<String, dynamic>> pushSyncBatch(
    List<Map<String, dynamic>> operations,
  ) async {
    final results = <Map<String, dynamic>>[];
    for (final operation in operations) {
      if (operation['action'] == 'create_order' ||
          operation['action'] == 'void_checkout') {
        final order = Order.fromJson(
          Map<String, dynamic>.from(operation['order'] as Map),
        );
        final deductions = (operation['deductions'] as List? ?? const [])
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        results.add(await pushOrderAtomic(
          order,
          deductions,
          managerUsername: operation['managerUsername'] as String?,
          managerPassword: operation['managerPassword'] as String?,
        ));
      } else {
        results.add({'ok': true});
      }
    }
    return {'ok': true, 'results': results};
  }

  @override
  Future<Map<String, dynamic>?> fetchFullStore() async => null;
}
