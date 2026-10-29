import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/supabase_config.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import '../models/inventory_item.dart';
import '../models/void_request.dart';
import '../models/restock_record.dart';
import '../models/staff_user.dart';
import '../models/login_activity.dart';
import '../models/print_job.dart';
import 'offline_credential_store.dart';

bool _hiveInitialized = false;
int _testBoxCounter = 0;

class _HivePreferences {
  final Box<dynamic> box;

  const _HivePreferences(this.box);

  String? getString(String key) {
    final value = box.get(key);
    if (value is String) return value;
    if (value is Map || value is List) return jsonEncode(value);
    return null;
  }

  bool? getBool(String key) => box.get(key) as bool?;

  List<String>? getStringList(String key) {
    final value = box.get(key);
    return value is List ? value.whereType<String>().toList() : null;
  }

  Future<void> setString(String key, String value) async {
    dynamic stored = value;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map || decoded is List) stored = decoded;
    } on FormatException {
      // Keep ordinary strings as strings in Hive.
    }
    await box.put(key, stored);
  }

  Future<void> setBool(String key, bool value) => box.put(key, value);

  Future<void> setStringList(String key, List<String> value) =>
      box.put(key, List<String>.of(value));

  Future<void> remove(String key) async {
    await box.delete(key);
  }
}

class LocalStorageService {
  final OfflineCredentialStore _offlineCredentialStore;

  LocalStorageService({OfflineCredentialStore? offlineCredentialStore})
      : _offlineCredentialStore =
            offlineCredentialStore ?? SecureOfflineCredentialStore();

  // Versioned cache keys so legacy hardcoded seed data is never loaded
  static const String _keyMenu = 'v2_cache_menu_items';
  static const String _keyCategories = 'v2_cache_categories';
  static const String _keyCategoryTypes = 'v1_pos_category_types';
  static const String _keyCategoryOrder = 'v1_pos_category_order';
  static const String _keyInventory = 'v2_cache_inventory';
  static const String _keyOrders = 'v2_cache_orders';
  static const String _keyStaff = 'v2_cache_staff_users';
  static const String _keyVoidRequests = 'v2_cache_void_requests';
  static const String _keyRestocks = 'v2_cache_restocks';
  static const String _keyLoginActivity = 'v2_cache_login_activity';
  static const String _keyPrintJobs = 'v2_cache_print_jobs';
  static const String _keyRecipesData = 'v2_cache_recipes_data';
  static const String _keyPosOpen = 'v2_cache_pos_is_open';
  static const String _keyPosOpenedBy = 'v2_cache_pos_opened_by';
  static const String _keyPosOpenedAt = 'v2_cache_pos_opened_at';
  static const String _keyPosFeatureSettings = 'v1_cache_pos_feature_settings';
  static const String _keyActiveStaffId = 'v1_active_staff_id';
  static const String _keyActiveStoreOwnerId = 'v1_active_store_owner_id';
  static const String _keyActiveStaffProfile = 'v1_active_staff_profile';
  static const String _keyPosApiToken = 'v1_pos_api_token';
  static const String _keyPosSyncCursor = 'v1_pos_sync_cursor';
  static const String _keyPosLastSyncAt = 'v1_pos_last_sync_at';
  static const String _keyActiveCheckout = 'v1_active_checkout';

  // Offline Queues (v2)
  static const String _queueOrders = 'v2_offline_queue_orders';
  static const String _queueRestocks = 'v2_offline_queue_restocks';
  static const String _queueRestockDeletes = 'v1_offline_queue_restock_deletes';
  static const String _queueVoidRequests = 'v2_offline_queue_void_requests';
  static const String _queueLoginActivity = 'v2_offline_queue_login_activity';
  static const String _queueInventory = 'v1_offline_queue_inventory';
  static const String _queueInventoryDeletes =
      'v1_offline_queue_inventory_deletes';

  static const String _keySupabaseUrl = 'supabase_url';
  static const String _keySupabaseAnonKey = 'supabase_anon_key';
  static const String _keyAdminApiUrl = 'admin_api_url';

  late _HivePreferences _prefs;
  Future<void>? _legacyCredentialMigration;

  Future<void> init() async {
    if (!_hiveInitialized) {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        final testDirectory =
            await Directory.systemTemp.createTemp('synorra_pos_test_');
        Hive.init(testDirectory.path);
      } else {
        await Hive.initFlutter();
      }
      _hiveInitialized = true;
    }
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    final boxName = isTest
        ? 'synorra_pos_local_test_${_testBoxCounter++}'
        : 'synorra_pos_local_v1';
    final box = await Hive.openBox<dynamic>(boxName);
    if (isTest) {
      await box.clear();
    }
    _prefs = _HivePreferences(box);

    final legacy = await SharedPreferences.getInstance();
    for (final key in legacy.getKeys()) {
      if (box.containsKey(key)) continue;
      final value = legacy.get(key);
      if (value is String) {
        dynamic stored = value;
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map || decoded is List) stored = decoded;
        } on FormatException {
          // Preserve non-JSON values exactly as they were stored.
        }
        await box.put(key, stored);
      } else if (value is bool ||
          value is num ||
          value is int ||
          value is double) {
        await box.put(key, value);
      } else if (value is List) {
        await box.put(key, value.toList());
      }
      await legacy.remove(key);
    }
    await migrateLegacyStaffCredentials();
  }

  Future<void> migrateLegacyStaffCredentials() {
    return _legacyCredentialMigration ??= _removeLegacyCachedStaffPasswords();
  }

  Future<void> _removeLegacyCachedStaffPasswords() async {
    final staff = getStaff();
    var containsLegacyPasswords = false;
    for (final user in staff) {
      if (user.password.isEmpty) continue;
      containsLegacyPasswords = true;
      if (user.id.isNotEmpty &&
          await getOfflineStaffCredential(user.id) == null) {
        await saveOfflineStaffCredential(user.id, user.password);
      }
    }
    if (containsLegacyPasswords) await saveStaff(staff);
  }

  String? getActiveStaffId() => _prefs.getString(_keyActiveStaffId);

  StaffUser? getActiveStaffProfile() {
    final raw = _prefs.getString(_keyActiveStaffProfile);
    if (raw == null) return null;
    try {
      return StaffUser.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  String? getPosApiToken() => _prefs.getString(_keyPosApiToken);

  String? getPosSyncCursor() => _prefs.getString(_keyPosSyncCursor);

  DateTime? getPosLastSyncAt() {
    final value = _prefs.getString(_keyPosLastSyncAt);
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<void> savePosLastSyncAt(DateTime value) =>
      _prefs.setString(_keyPosLastSyncAt, value.toUtc().toIso8601String());

  Future<void> savePosSyncCursor(String cursor) =>
      _prefs.setString(_keyPosSyncCursor, cursor);

  Future<void> saveOfflineStaffCredential(
    String staffId,
    String password,
  ) =>
      _offlineCredentialStore.save(staffId: staffId, password: password);

  Future<String?> getOfflineStaffCredential(String staffId) =>
      _offlineCredentialStore.read(staffId: staffId);

  Future<void> removeOfflineStaffCredential(String staffId) =>
      _offlineCredentialStore.remove(staffId: staffId);

  Future<void> saveActiveStaffSession(
    StaffUser staff, {
    String? posApiToken,
  }) async {
    final nextOwnerId = staff.role.toLowerCase() == 'cashier' ? staff.id : null;
    final previousOwnerId = _prefs.getString(_keyActiveStoreOwnerId) ??
        ((getActiveStaffProfile()?.role.toLowerCase() == 'cashier')
            ? getActiveStaffProfile()?.id
            : null);
    if (nextOwnerId != null && previousOwnerId != nextOwnerId) {
      if (getPendingSyncCount() > 0) {
        throw StateError(
            'Sync this Owner’s pending POS changes before switching accounts.');
      }
      for (final key in <String>[
        _keyMenu,
        _keyCategories,
        _keyCategoryOrder,
        _keyInventory,
        _keyOrders,
        _keyStaff,
        _keyVoidRequests,
        _keyRestocks,
        _keyLoginActivity,
        _keyPrintJobs,
        _keyRecipesData,
        _keyPosOpen,
        _keyPosOpenedBy,
        _keyPosOpenedAt,
        _keyPosFeatureSettings,
        _keyActiveCheckout,
        _keyPosApiToken,
        _keyPosLastSyncAt,
      ]) {
        await _prefs.remove(key);
      }
    }
    if (nextOwnerId != null) {
      await _prefs.setString(_keyActiveStoreOwnerId, nextOwnerId);
    }
    if (previousOwnerId != nextOwnerId) {
      await _prefs.remove(_keyPosSyncCursor);
    }
    await _prefs.setString(_keyActiveStaffId, staff.id);
    await _prefs.setString(
      _keyActiveStaffProfile,
      jsonEncode({
        'id': staff.id,
        'username': staff.username,
        'name': staff.name,
        'role': staff.role,
        'title': staff.title,
      }),
    );
    if (posApiToken != null && posApiToken.isNotEmpty) {
      await _prefs.setString(_keyPosApiToken, posApiToken);
    }
  }

  Future<void> clearActiveStaffId() async {
    await _prefs.remove(_keyActiveStaffId);
    await _prefs.remove(_keyActiveStaffProfile);
    await _prefs.remove(_keyPosApiToken);
  }

  // --- Connection Config ---
  String? getSupabaseUrl() => SupabaseConfig.projectUrl;

  String? getSupabaseAnonKey() => SupabaseConfig.anonKey;

  String? getAdminApiUrl() {
    final savedUrl = _prefs.getString(_keyAdminApiUrl);
    return SupabaseConfig.normalizePosApiUrl(
      savedUrl ?? SupabaseConfig.adminApiBaseUrl,
    );
  }

  Future<void> setSupabaseConfig(String url, String anonKey,
      {String? adminApiUrl}) async {
    await _prefs.remove(_keySupabaseUrl);
    await _prefs.remove(_keySupabaseAnonKey);
    await _prefs.remove(_keyAdminApiUrl);
  }

  Future<void> setAdminApiUrl(String adminApiUrl) async {
    final normalizedUrl = SupabaseConfig.normalizePosApiUrl(adminApiUrl);
    if (getAdminApiUrl() != normalizedUrl) {
      await _prefs.remove(_keyPosSyncCursor);
    }
    await _prefs.setString(_keyAdminApiUrl, normalizedUrl);
  }

  // --- POS State ---
  bool getPosIsOpen() => _prefs.getBool(_keyPosOpen) ?? false;
  String? getPosOpenedBy() => _prefs.getString(_keyPosOpenedBy);
  String? getPosOpenedAt() => _prefs.getString(_keyPosOpenedAt);

  Future<void> setPosState(
      {required bool isOpen, String? openedBy, String? openedAt}) async {
    await _prefs.setBool(_keyPosOpen, isOpen);
    if (openedBy != null) await _prefs.setString(_keyPosOpenedBy, openedBy);
    if (openedAt != null) await _prefs.setString(_keyPosOpenedAt, openedAt);
  }

  Map<String, dynamic>? getCachedPosFeatureSettings() {
    final raw = _prefs.getString(_keyPosFeatureSettings);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCachedPosFeatureSettings({
    required bool inventoryFeaturesEnabled,
    required bool printButtonHidden,
    required String attendanceAuthMode,
    required List<int> attendanceWorkdays,
    required String attendanceStartTime,
    required Map<String, dynamic> permissions,
  }) async {
    await _prefs.setString(
      _keyPosFeatureSettings,
      jsonEncode({
        'inventoryFeaturesEnabled': inventoryFeaturesEnabled,
        'printButtonHidden': printButtonHidden,
        'attendanceAuthMode': attendanceAuthMode,
        'attendanceWorkdays': attendanceWorkdays,
        'attendanceStartTime': attendanceStartTime,
        'permissions': permissions,
      }),
    );
  }

  Future<void> saveActiveCheckout({
    required List<OrderItem> items,
    required String paymentMethod,
    required double tenderedAmount,
    String serviceMode = 'dine-in',
    required double discountAmount,
    String? promoId,
    String? promoLabel,
    int? promoItemIndex,
    int? promoItemQty,
    String? pendingVoidRequestId,
  }) async {
    if (items.isEmpty) {
      await clearActiveCheckout();
      return;
    }
    await _prefs.setString(
      _keyActiveCheckout,
      jsonEncode({
        'items': items.map((item) => item.toJson()).toList(),
        'paymentMethod': paymentMethod,
        'tenderedAmount': tenderedAmount,
        'serviceMode': serviceMode,
        'discountAmount': discountAmount,
        'promoId': promoId,
        'promoLabel': promoLabel,
        'promoItemIndex': promoItemIndex,
        'promoItemQty': promoItemQty,
        'pendingVoidRequestId': pendingVoidRequestId,
      }),
    );
  }

  Map<String, dynamic>? getActiveCheckout() {
    final raw = _prefs.getString(_keyActiveCheckout);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearActiveCheckout() async {
    await _prefs.remove(_keyActiveCheckout);
  }

  // --- Menu Cache ---
  Future<void> saveMenu(List<MenuItem> items) async {
    final list = items.map((i) => i.toJson()).toList();
    await _prefs.setString(_keyMenu, jsonEncode(list));
  }

  List<MenuItem> getMenu() {
    final raw = _prefs.getString(_keyMenu);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => MenuItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // --- Categories Cache (Strictly dynamic from Admin) ---
  Future<void> saveCategories(List<String> categories) async {
    final normalized = <String>['All'];
    for (final c in categories) {
      final trimmed = c.trim();
      if (trimmed.isNotEmpty &&
          trimmed.toLowerCase() != 'all' &&
          !normalized.any(
              (existing) => existing.toLowerCase() == trimmed.toLowerCase())) {
        normalized.add(trimmed);
      }
    }
    await _prefs.setStringList(_keyCategories, normalized);
  }

  List<String> getCategories() {
    return _prefs.getStringList(_keyCategories) ?? ['All'];
  }

  Future<void> saveCategoryTypes(Map<String, String> categoryTypes) async {
    final normalized = <String, String>{};
    for (final entry in categoryTypes.entries) {
      final category = entry.key.trim();
      final type = entry.value.trim();
      if (category.isNotEmpty && type.isNotEmpty) {
        normalized[category] = type;
      }
    }
    await _prefs.setString(_keyCategoryTypes, jsonEncode(normalized));
  }

  Map<String, String> getCategoryTypes() {
    final raw = _prefs.getString(_keyCategoryTypes);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.entries.fold<Map<String, String>>({}, (result, entry) {
        final category = entry.key.toString().trim();
        final type = entry.value.toString().trim();
        if (category.isNotEmpty && type.isNotEmpty) {
          result[category] = type;
        }
        return result;
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> saveCategoryOrder(List<String> categories) async {
    await _prefs.setStringList(_keyCategoryOrder, categories);
  }

  List<String> getCategoryOrder() {
    return _prefs.getStringList(_keyCategoryOrder) ?? [];
  }

  // --- Inventory Cache ---
  Future<void> saveInventory(List<InventoryItem> items) async {
    final list = items.map((i) => i.toJson()).toList();
    await _prefs.setString(_keyInventory, jsonEncode(list));
  }

  List<InventoryItem> getInventory() {
    final raw = _prefs.getString(_keyInventory);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) =>
              InventoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> queueInventoryItem(InventoryItem item) async {
    final queue = getPendingInventoryItems()
      ..removeWhere((entry) => entry.id == item.id)
      ..add(item);
    await _prefs.setString(
      _queueInventory,
      jsonEncode(queue.map((entry) => entry.toJson()).toList()),
    );
    final deletes = getPendingInventoryDeletes()..remove(item.id);
    await _prefs.setStringList(_queueInventoryDeletes, deletes);
  }

  List<InventoryItem> getPendingInventoryItems() {
    final raw = _prefs.getString(_queueInventory);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((entry) =>
              InventoryItem.fromJson(Map<String, dynamic>.from(entry as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> removePendingInventoryItem(String id) async {
    final queue = getPendingInventoryItems()
      ..removeWhere((item) => item.id == id);
    await _prefs.setString(
      _queueInventory,
      jsonEncode(queue.map((item) => item.toJson()).toList()),
    );
  }

  List<String> getPendingInventoryDeletes() =>
      _prefs.getStringList(_queueInventoryDeletes) ?? [];

  Future<void> queueInventoryDelete(String id) async {
    await removePendingInventoryItem(id);
    final deletes = getPendingInventoryDeletes();
    if (!deletes.contains(id)) deletes.add(id);
    await _prefs.setStringList(_queueInventoryDeletes, deletes);
  }

  Future<void> removePendingInventoryDelete(String id) async {
    final deletes = getPendingInventoryDeletes()..remove(id);
    await _prefs.setStringList(_queueInventoryDeletes, deletes);
  }

  // --- Recipes, RecipeCostings, Costings & UsageLogs Cache ---
  Future<void> saveRecipesData(Map<String, dynamic> data) async {
    await _prefs.setString(_keyRecipesData, jsonEncode(data));
  }

  Map<String, dynamic> getRecipesData() {
    final raw = _prefs.getString(_keyRecipesData);
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  // --- Orders Cache ---
  Future<void> saveOrders(List<Order> orders) async {
    final list = orders.map((o) => o.toJson()).toList();
    await _prefs.setString(_keyOrders, jsonEncode(list));
  }

  List<Order> getOrders() {
    final raw = _prefs.getString(_keyOrders);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Order.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addOrder(Order order) async {
    final orders = getOrders();
    orders.removeWhere((o) => o.id == order.id);
    orders.insert(0, order);
    await saveOrders(orders);

    if (!order.isSynced) {
      await enqueueOrder(order);
    }
  }

  // --- Offline Order Queue ---
  Future<void> enqueueOrder(Order order) async {
    final queue = getPendingOrders();
    queue.removeWhere((o) => o.id == order.id);
    queue.add(order);
    await _prefs.setString(
        _queueOrders, jsonEncode(queue.map((o) => o.toJson()).toList()));
  }

  List<Order> getPendingOrders() {
    final raw = _prefs.getString(_queueOrders);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Order.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> removePendingOrder(String id) async {
    final queue = getPendingOrders();
    queue.removeWhere((o) => o.id == id);
    await _prefs.setString(
        _queueOrders, jsonEncode(queue.map((o) => o.toJson()).toList()));
  }

  // --- Restocks Cache & Queue ---
  Future<void> saveRestocks(List<RestockRecord> records) async {
    await _prefs.setString(
        _keyRestocks, jsonEncode(records.map((r) => r.toJson()).toList()));
  }

  List<RestockRecord> getRestocks() {
    final raw = _prefs.getString(_keyRestocks);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) =>
              RestockRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addRestock(RestockRecord record) async {
    final list = getRestocks();
    list.removeWhere((r) => r.id == record.id);
    list.insert(0, record);
    await saveRestocks(list);

    if (!record.isSynced) {
      final queue = getPendingRestocks();
      queue.removeWhere((r) => r.id == record.id);
      queue.add(record);
      await _prefs.setString(
          _queueRestocks, jsonEncode(queue.map((r) => r.toJson()).toList()));
    }
  }

  List<RestockRecord> getPendingRestocks() {
    final raw = _prefs.getString(_queueRestocks);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) =>
              RestockRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> removePendingRestock(String id) async {
    final queue = getPendingRestocks();
    queue.removeWhere((r) => r.id == id);
    await _prefs.setString(
        _queueRestocks, jsonEncode(queue.map((r) => r.toJson()).toList()));
  }

  List<String> getPendingRestockDeletes() =>
      _prefs.getStringList(_queueRestockDeletes) ?? [];

  Future<void> addPendingRestockDelete(String id) async {
    final queue = getPendingRestockDeletes();
    if (!queue.contains(id)) queue.add(id);
    await _prefs.setStringList(_queueRestockDeletes, queue);
  }

  Future<void> removePendingRestockDelete(String id) async {
    final queue = getPendingRestockDeletes()
      ..removeWhere((pendingId) => pendingId == id);
    await _prefs.setStringList(_queueRestockDeletes, queue);
  }

  // --- Void Requests Cache & Queue ---
  Future<void> saveVoidRequests(List<VoidRequest> requests) async {
    await _prefs.setString(
        _keyVoidRequests, jsonEncode(requests.map((r) => r.toJson()).toList()));
  }

  List<VoidRequest> getVoidRequests() {
    final raw = _prefs.getString(_keyVoidRequests);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => VoidRequest.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addVoidRequest(VoidRequest request) async {
    final list = getVoidRequests();
    list.removeWhere((r) => r.id == request.id);
    list.insert(0, request);
    await saveVoidRequests(list);

    if (!request.isSynced) {
      final queue = getPendingVoidRequests();
      queue.removeWhere((r) => r.id == request.id);
      queue.add(request);
      await _prefs.setString(_queueVoidRequests,
          jsonEncode(queue.map((r) => r.toJson()).toList()));
    }
  }

  List<VoidRequest> getPendingVoidRequests() {
    final raw = _prefs.getString(_queueVoidRequests);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => VoidRequest.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> removePendingVoidRequest(String id) async {
    final queue = getPendingVoidRequests();
    queue.removeWhere((r) => r.id == id);
    await _prefs.setString(
        _queueVoidRequests, jsonEncode(queue.map((r) => r.toJson()).toList()));
  }

  // --- Staff Users Cache ---
  Future<void> saveStaff(List<StaffUser> staff) async {
    await _prefs.setString(
        _keyStaff, jsonEncode(staff.map((s) => s.toJson()).toList()));
  }

  List<StaffUser> getStaff() {
    final raw = _prefs.getString(_keyStaff);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => StaffUser.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // --- Login Activity / Shift Punches ---
  Future<void> saveLoginActivity(List<LoginActivity> logs) async {
    await _prefs.setString(
        _keyLoginActivity, jsonEncode(logs.map((l) => l.toJson()).toList()));
  }

  List<LoginActivity> getLoginActivity() {
    final raw = _prefs.getString(_keyLoginActivity);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) =>
              LoginActivity.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addLoginActivity(LoginActivity activity) async {
    final list = getLoginActivity();
    list.removeWhere((l) => l.id == activity.id);
    list.insert(0, activity);
    await saveLoginActivity(list);

    if (!activity.isSynced) {
      final queue = getPendingLoginActivity();
      queue.removeWhere((l) => l.id == activity.id);
      queue.add(activity);
      await _prefs.setString(_queueLoginActivity,
          jsonEncode(queue.map((l) => l.toJson()).toList()));
    }
  }

  List<LoginActivity> getPendingLoginActivity() {
    final raw = _prefs.getString(_queueLoginActivity);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) =>
              LoginActivity.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> removePendingLoginActivity(String id) async {
    final queue = getPendingLoginActivity();
    queue.removeWhere((l) => l.id == id);
    await _prefs.setString(
        _queueLoginActivity, jsonEncode(queue.map((l) => l.toJson()).toList()));
  }

  // --- Print Jobs ---
  Future<void> savePrintJobs(List<PrintJob> jobs) async {
    await _prefs.setString(
        _keyPrintJobs, jsonEncode(jobs.map((j) => j.toJson()).toList()));
  }

  List<PrintJob> getPrintJobs() {
    final raw = _prefs.getString(_keyPrintJobs);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => PrintJob.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  int getPendingSyncCount() {
    return getPendingOrders().length +
        getPendingRestocks().length +
        getPendingRestockDeletes().length +
        getPendingVoidRequests().length +
        getPendingLoginActivity().length +
        getPendingInventoryItems().length +
        getPendingInventoryDeletes().length;
  }

  Future<void> clearPendingQueues() async {
    await _prefs.remove(_queueOrders);
    await _prefs.remove(_queueRestocks);
    await _prefs.remove(_queueRestockDeletes);
    await _prefs.remove(_queueVoidRequests);
    await _prefs.remove(_queueLoginActivity);
    await _prefs.remove(_queueInventory);
    await _prefs.remove(_queueInventoryDeletes);
  }
}
