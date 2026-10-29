import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'local_storage_service.dart';
import 'offline_image_cache.dart';
import 'supabase_service.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import '../models/inventory_item.dart';
import '../models/restock_record.dart';
import '../models/staff_user.dart';
import '../models/void_request.dart';
import '../models/login_activity.dart';

enum SyncStatus { idle, syncing, success, error, offline }

class SyncService extends ChangeNotifier {
  static const Duration syncInterval = Duration(hours: 5);

  final LocalStorageService localStorage;
  final SupabaseService supabaseService;

  @visibleForTesting
  static List<T> mergeById<T>({
    required List<T> current,
    required List<T> updates,
    required String Function(T) idOf,
    Set<String> deletedIds = const {},
    Set<String> preserveIds = const {},
  }) {
    final merged = <String, T>{};
    for (final item in current) {
      final id = idOf(item);
      if (id.isNotEmpty &&
          (!deletedIds.contains(id) || preserveIds.contains(id))) {
        merged[id] = item;
      }
    }
    for (final item in updates) {
      final id = idOf(item);
      if (id.isEmpty ||
          (deletedIds.contains(id) && !preserveIds.contains(id))) {
        continue;
      }
      if (preserveIds.contains(id) && merged.containsKey(id)) continue;
      merged[id] = item;
    }
    return merged.values.toList();
  }

  @visibleForTesting
  static List<MenuItem> mergeMenuPreservingLocal(
    List<MenuItem> localMenu,
    List<MenuItem> remoteMenu,
  ) {
    final combined = <String, MenuItem>{};
    for (final item in localMenu) {
      if (item.id.trim().isNotEmpty) {
        combined[item.id] = item;
      }
    }
    for (final item in remoteMenu) {
      if (item.id.trim().isNotEmpty && !combined.containsKey(item.id)) {
        combined[item.id] = item;
      }
    }
    return combined.values.toList();
  }

  @visibleForTesting
  static List<String> mergeCategoriesPreservingLocal(
    List<String> localCategories,
    List<String> remoteCategories,
  ) {
    final merged = <String>[];
    final seen = <String>{};

    void addCategory(String category) {
      final normalized = category.trim();
      if (normalized.isEmpty || normalized.toLowerCase() == 'all') {
        return;
      }
      final key = normalized.toLowerCase();
      if (!seen.contains(key)) {
        seen.add(key);
        merged.add(normalized);
      }
    }

    for (final category in localCategories) {
      addCategory(category);
    }
    for (final category in remoteCategories) {
      addCategory(category);
    }
    return ['All', ...merged];
  }

  @visibleForTesting
  static List<String> mergeCategoryOrderPreservingLocal(
    List<String> localOrder,
    List<String> remoteCategories,
  ) {
    final merged = <String>[];
    final seen = <String>{};

    void addCategory(String category) {
      final normalized = category.trim();
      if (normalized.isEmpty || normalized.toLowerCase() == 'all') {
        return;
      }
      final key = normalized.toLowerCase();
      if (!seen.contains(key)) {
        seen.add(key);
        merged.add(normalized);
      }
    }

    for (final category in localOrder) {
      addCategory(category);
    }
    for (final category in remoteCategories) {
      addCategory(category);
    }
    return merged;
  }

  SyncStatus status = SyncStatus.idle;
  bool isOnline = true;
  bool inventoryFeaturesEnabled = true;
  bool printButtonHidden = false;
  String attendanceAuthMode = 'username_password';
  List<int> attendanceWorkdays = [1, 2, 3, 4, 5];
  String attendanceStartTime = '09:00';
  final Map<String, bool> ownerPermissions = {
    'stockInventory': true,
    'restockInventory': true,
    'connectLabels': true,
    'connectslip': true,
    'printButton': true,
    'internalslip': true,
    'cupLabels': true,
    'dineIn': true,
    'takeOut': true,
    'promotionDiscount': false,
    'promotionsEnabled': false,
    'wasteManagement': true,
  };
  List<Map<String, dynamic>> promotionCodes = [];

  bool hasPermission(String key) => ownerPermissions[key] ?? true;
  String? lastError;
  DateTime? lastSyncTime;
  int pendingCount = 0;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _periodicSyncTimer;
  Future<void>? _activeSyncFuture;
  Future<bool>? _activeCredentialRefreshFuture;
  DateTime? _lastCredentialRefreshAttempt;
  VoidCallback? onSyncCompleted;

  SyncService({
    required this.localStorage,
    required this.supabaseService,
  }) {
    final cachedSettings = localStorage.getCachedPosFeatureSettings();
    if (cachedSettings != null) {
      inventoryFeaturesEnabled =
          cachedSettings['inventoryFeaturesEnabled'] != false;
      printButtonHidden = cachedSettings['printButtonHidden'] == true;
      final cachedAuthMode = cachedSettings['attendanceAuthMode'];
      if (cachedAuthMode is String &&
          const {
            'username_password',
            'photo_username_password',
            'photo_full_name_pin',
          }.contains(cachedAuthMode)) {
        attendanceAuthMode = cachedAuthMode;
      }
      final cachedWorkdays = cachedSettings['attendanceWorkdays'];
      if (cachedWorkdays is List) {
        attendanceWorkdays = cachedWorkdays
            .whereType<num>()
            .map((day) => day.toInt())
            .where((day) => day >= 1 && day <= 7)
            .toSet()
            .toList()
          ..sort();
      }
      final cachedStartTime = cachedSettings['attendanceStartTime'];
      if (cachedStartTime is String && cachedStartTime.length >= 5) {
        attendanceStartTime = cachedStartTime.substring(0, 5);
      }
      final cachedPermissions = cachedSettings['permissions'];
      if (cachedPermissions is Map) {
        for (final key in ownerPermissions.keys.toList()) {
          if (cachedPermissions.containsKey(key)) {
            ownerPermissions[key] = cachedPermissions[key] == true;
          }
        }
      }
    }
  }

  void start() {
    updatePendingCount();

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final connected = results.any((r) => r != ConnectivityResult.none);
      isOnline = connected;
      if (!connected) {
        status = SyncStatus.offline;
      } else if (status == SyncStatus.offline) {
        status = SyncStatus.idle;
      }
      notifyListeners();
    });

    if (localStorage.getPosSyncCursor() == null) {
      // Initial bootstrap is the one-time setup exception to scheduled sync.
      unawaited(syncNow());
    } else {
      _scheduleNextBatchSync();
    }
  }

  void _scheduleNextBatchSync() {
    _periodicSyncTimer?.cancel();
    var lastSync = localStorage.getPosLastSyncAt();
    if (lastSync == null) {
      lastSync = DateTime.now();
      unawaited(localStorage.savePosLastSyncAt(lastSync));
    }
    final delay = lastSync.add(syncInterval).difference(DateTime.now());
    _periodicSyncTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(syncNow()),
    );
  }

  void disposeService() {
    _connectivitySub?.cancel();
    _periodicSyncTimer?.cancel();
  }

  int getPendingCount() {
    pendingCount = localStorage.getPendingSyncCount();
    return pendingCount;
  }

  void updatePendingCount() {
    pendingCount = localStorage.getPendingSyncCount();
    notifyListeners();
  }

  /// Force an on-demand sync, bypassing the five-hour schedule.
  Future<void> syncNow() async {
    if (_activeSyncFuture != null) {
      return _activeSyncFuture!;
    }
    _activeSyncFuture = _performSync();
    try {
      await _activeSyncFuture;
    } finally {
      _activeSyncFuture = null;
      _scheduleNextBatchSync();
    }
  }

  Future<void> syncAll() => syncNow();

  Future<bool> ensurePosApiToken({bool forceRefresh = false}) async {
    if (supabaseService.hasPosApiToken &&
        !supabaseService.isPosApiTokenExpired) {
      return true;
    }
    if (!isOnline) return false;

    final activeRefresh = _activeCredentialRefreshFuture;
    if (activeRefresh != null) return activeRefresh;

    final now = DateTime.now();
    if (!forceRefresh &&
        _lastCredentialRefreshAttempt != null &&
        now.difference(_lastCredentialRefreshAttempt!) <
            const Duration(seconds: 30)) {
      return false;
    }
    _lastCredentialRefreshAttempt = now;

    final refresh = _refreshPosApiToken();
    _activeCredentialRefreshFuture = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_activeCredentialRefreshFuture, refresh)) {
        _activeCredentialRefreshFuture = null;
      }
    }
  }

  Future<bool> _refreshPosApiToken() async {
    final activeStaff = localStorage.getActiveStaffProfile();
    final candidates = <StaffUser>[];
    if (activeStaff != null) candidates.add(activeStaff);
    for (final activity in localStorage.getPendingLoginActivity()) {
      if (activity.userId.isEmpty ||
          candidates.any((staff) => staff.id == activity.userId)) {
        continue;
      }
      candidates.add(StaffUser(
        id: activity.userId,
        username: activity.username,
        password: '',
        name: activity.name,
        role: activity.role,
      ));
    }

    for (final staff in candidates) {
      final password = await localStorage.getOfflineStaffCredential(staff.id);
      if (password == null || password.isEmpty) continue;

      final auth = await supabaseService.authenticateStaff(
        staff.username,
        password,
        persistSessionToken: false,
      );
      if (auth['ok'] != true || auth['user'] is! StaffUser) continue;

      final authenticatedStaff = auth['user'] as StaffUser;
      final token = auth['token']?.toString() ?? '';
      if (authenticatedStaff.id != staff.id || token.isEmpty) continue;

      supabaseService.setPosApiToken(token);
      if (activeStaff?.id == authenticatedStaff.id) {
        await localStorage.saveActiveStaffSession(
          authenticatedStaff,
          posApiToken: token,
        );
      }
      return true;
    }
    return false;
  }

  Future<void> _performSync() async {
    await localStorage.savePosLastSyncAt(DateTime.now());
    if (!isOnline || !await ensurePosApiToken()) {
      status = isOnline ? SyncStatus.idle : SyncStatus.offline;
      lastError = null;
      updatePendingCount();
      return;
    }

    status = SyncStatus.syncing;
    lastError = null;
    notifyListeners();

    try {
      // Flush queued writes in a single request before pulling the change feed.
      final pendingOrders = localStorage.getPendingOrders();
      final pendingRestocks = localStorage.getPendingRestocks();
      final pendingRestockDeletes = localStorage.getPendingRestockDeletes();
      final pendingInventory = localStorage.getPendingInventoryItems();
      final pendingInventoryDeletes = localStorage.getPendingInventoryDeletes();
      final pendingPunches = localStorage.getPendingLoginActivity();
      final pendingVoids = localStorage.getPendingVoidRequests();
      final operations = <Map<String, dynamic>>[];
      final operationRefs = <({String kind, String id, Object record})>[];

      void addOperation(
        String kind,
        String id,
        Object record,
        Map<String, dynamic> operation,
      ) {
        operations.add(operation);
        operationRefs.add((kind: kind, id: id, record: record));
      }

      for (final order in pendingOrders) {
        if (order.voided) {
          final manager = localStorage
              .getStaff()
              .where((staff) => staff.id == order.voidedBy)
              .firstOrNull;
          final managerPassword = manager == null
              ? null
              : await localStorage.getOfflineStaffCredential(manager.id);
          if (manager == null ||
              managerPassword == null ||
              managerPassword.isEmpty) {
            debugPrint(
              'Pending void sync skipped (${order.id}): approving manager credentials are unavailable.',
            );
            continue;
          }
          addOperation(
            'order',
            order.id,
            order,
            order.ticketNo.trim().isEmpty
                ? {
                    'action': 'void_checkout',
                    'order': order.toJson(),
                    'reason': order.voidReason ?? 'Voided from POS',
                    'managerUsername': manager.username,
                    'managerPassword': managerPassword,
                  }
                : {
                    'action': 'void_order',
                    'orderId': order.id,
                    'reason': order.voidReason ?? 'Voided from POS',
                    'managerUsername': manager.username,
                    'managerPassword': managerPassword,
                  },
          );
          continue;
        }
        addOperation(
          'order',
          order.id,
          order,
          {
            'action': 'create_order',
            'order': order.toJson(),
            'deductions': buildDeductionsForOrder(order),
          },
        );
      }
      for (final restock in pendingRestocks) {
        addOperation('restock', restock.id, restock, {
          'action': 'create_restock',
          'restock': restock.toJson(),
        });
      }
      for (final id in pendingRestockDeletes) {
        addOperation('restock_delete', id, id, {
          'action': 'delete_restock',
          'id': id,
        });
      }
      for (final item in pendingInventory) {
        addOperation('inventory', item.id, item, {
          'action': 'upsert_inventory_item',
          'item': item.toJson(),
        });
      }
      for (final id in pendingInventoryDeletes) {
        addOperation('inventory_delete', id, id, {
          'action': 'delete_inventory_item',
          'id': id,
        });
      }
      for (final punch in pendingPunches) {
        addOperation('login_activity', punch.id, punch, {
          'action': 'login_activity',
          'activity': punch.toJson(),
        });
      }
      for (final request in pendingVoids) {
        addOperation('void_request', request.id, request, {
          'action': 'create_void_request',
          'request': request.toJson(),
        });
      }

      for (var start = 0; start < operations.length; start += 100) {
        final end = (start + 100).clamp(0, operations.length);
        final batch = await supabaseService.pushSyncBatch(
          operations.sublist(start, end),
        );
        if (batch['ok'] != true || batch['results'] is! List) {
          debugPrint(
            'POS batch sync failed: ${batch['error'] ?? 'Invalid batch response'}',
          );
          continue;
        }
        final results = batch['results'] as List;
        for (var index = 0; index < end - start; index++) {
          if (index >= results.length || results[index] is! Map) continue;
          final result = Map<String, dynamic>.from(results[index] as Map);
          if (result['ok'] != true) {
            debugPrint(
              'Queued ${operationRefs[start + index].kind} sync failed '
              '(${operationRefs[start + index].id}): '
              '${result['error'] ?? 'Unknown server error'}',
            );
            continue;
          }
          final ref = operationRefs[start + index];
          switch (ref.kind) {
            case 'order':
              final order = ref.record as Order;
              order.isSynced = true;
              if (result['ticketNo'] != null &&
                  result['ticketNo'].toString().isNotEmpty) {
                order.ticketNo = result['ticketNo'].toString();
              }
              await localStorage.addOrder(order);
              await localStorage.removePendingOrder(order.id);
            case 'restock':
              final restock = ref.record as RestockRecord;
              restock.isSynced = true;
              await localStorage.removePendingRestock(restock.id);
            case 'restock_delete':
              await localStorage.removePendingRestockDelete(ref.id);
            case 'inventory':
              await localStorage.removePendingInventoryItem(ref.id);
            case 'inventory_delete':
              await localStorage.removePendingInventoryDelete(ref.id);
            case 'login_activity':
              final punch = ref.record as LoginActivity;
              punch.isSynced = true;
              await localStorage.removePendingLoginActivity(punch.id);
            case 'void_request':
              final request = ref.record as VoidRequest;
              request.isSynced = true;
              await localStorage.removePendingVoidRequest(request.id);
          }
        }
      }

      // 2. Bootstrap once, then pull bounded change-feed pages.
      var cursor = localStorage.getPosSyncCursor();
      if (cursor == null) {
        final bootstrap = await supabaseService.fetchFullStore();
        if (bootstrap == null) {
          throw StateError('Unable to sync with the authenticated POS server.');
        }
        if (bootstrap['mode'] != 'bootstrap') {
          throw StateError('POS server did not return an initial bootstrap.');
        }
        final nextCursor = bootstrap['cursor']?.toString();
        if (nextCursor == null || !RegExp(r'^\d+$').hasMatch(nextCursor)) {
          throw StateError('POS bootstrap did not return a valid sync cursor.');
        }
        await _applyBootstrap(bootstrap);
        await localStorage.savePosSyncCursor(nextCursor);
      } else {
        var activeCursor = cursor;
        var hasMore = true;
        while (hasMore) {
          final delta = await supabaseService.fetchPosSyncDelta(activeCursor);
          if (delta == null || delta['mode'] != 'delta') {
            throw StateError('Unable to fetch incremental POS changes.');
          }
          final nextCursor = delta['cursor']?.toString();
          if (nextCursor == null || !RegExp(r'^\d+$').hasMatch(nextCursor)) {
            throw StateError('POS change feed returned an invalid cursor.');
          }
          if (delta['hasMore'] == true && nextCursor == activeCursor) {
            throw StateError('POS change feed pagination did not advance.');
          }
          if (BigInt.parse(nextCursor) < BigInt.parse(activeCursor)) {
            throw StateError('POS change feed cursor moved backwards.');
          }
          await _applyDelta(delta);
          await localStorage.savePosSyncCursor(nextCursor);
          activeCursor = nextCursor;
          hasMore = delta['hasMore'] == true;
        }
      }

      status = SyncStatus.success;
      isOnline = true;
      lastSyncTime = DateTime.now();
      onSyncCompleted?.call();
    } catch (e) {
      debugPrint('Sync warning: $e');
      status = SyncStatus.error;
      lastError = e.toString();
    } finally {
      updatePendingCount();
    }
  }

  List<Map<String, dynamic>> _syncRows(Object? value) => value is List
      ? value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList()
      : <Map<String, dynamic>>[];

  void _sortOrdersNewestFirst(List<Order> orders) {
    int epoch(Order order) =>
        DateTime.tryParse(order.createdAt)?.millisecondsSinceEpoch ?? 0;
    orders.sort((left, right) => epoch(right).compareTo(epoch(left)));
  }

  Set<String> _deletedIds(Map<String, dynamic> delta, String key) {
    final deleted = delta['deleted'];
    if (deleted is! Map || deleted[key] is! List) return <String>{};
    return (deleted[key] as List).map((id) => id.toString()).toSet();
  }

  Future<void> _applyPosSettings(Object? value) async {
    if (value is! Map) return;
    final posState = Map<String, dynamic>.from(value);
    inventoryFeaturesEnabled = posState['inventoryFeaturesEnabled'] != false;
    printButtonHidden = posState['printButtonHidden'] == true;
    final authMode = posState['attendanceAuthMode'];
    if (authMode is String &&
        const {
          'username_password',
          'photo_username_password',
          'photo_full_name_pin',
        }.contains(authMode)) {
      attendanceAuthMode = authMode;
    }
    final workdays = posState['attendanceWorkdays'];
    if (workdays is List) {
      attendanceWorkdays = workdays
          .whereType<num>()
          .map((day) => day.toInt())
          .where((day) => day >= 1 && day <= 7)
          .toSet()
          .toList()
        ..sort();
    }
    final startTime = posState['attendanceStartTime'];
    if (startTime is String && startTime.length >= 5) {
      attendanceStartTime = startTime.substring(0, 5);
    }
    await localStorage.saveCachedPosFeatureSettings(
      inventoryFeaturesEnabled: inventoryFeaturesEnabled,
      printButtonHidden: printButtonHidden,
      attendanceAuthMode: attendanceAuthMode,
      attendanceWorkdays: attendanceWorkdays,
      attendanceStartTime: attendanceStartTime,
      permissions: ownerPermissions,
    );
  }

  Future<void> _applyUsers(
    List<Map<String, dynamic>> users, {
    Set<String> deletedIds = const {},
    bool replace = false,
  }) async {
    final freshStaff = users.map(StaffUser.fromJson).toList();
    final staff = replace
        ? freshStaff
        : mergeById(
            current: localStorage.getStaff(),
            updates: freshStaff,
            idOf: (user) => user.id,
            deletedIds: deletedIds,
          );
    if (replace && deletedIds.isNotEmpty) {
      staff.removeWhere((user) => deletedIds.contains(user.id));
    }
    await localStorage.saveStaff(staff);
    for (final user in users) {
      final avatarPath = user['avatarPath']?.toString().trim() ?? '';
      final staffId = user['id']?.toString() ?? '';
      if (avatarPath.isNotEmpty && staffId.isNotEmpty) {
        unawaited(_cacheStaffAvatar(staffId, avatarPath));
      }
    }

    final activeId = localStorage.getActiveStaffId();
    final activeUser =
        users.where((user) => user['id']?.toString() == activeId).firstOrNull;
    final ownerUser = users
        .where(
          (user) => user['role']?.toString().toLowerCase() == 'cashier',
        )
        .firstOrNull;
    final permissions = (ownerUser ?? activeUser)?['permissions'];
    promotionCodes = [];
    if (permissions is Map) {
      for (final key in ownerPermissions.keys.toList()) {
        ownerPermissions[key] = permissions[key] != false;
      }
      ownerPermissions['promotionDiscount'] =
          permissions['promotionDiscount'] == true;
      ownerPermissions['promotionsEnabled'] =
          permissions['promotionsEnabled'] == true;
      final rawPromotions = permissions['promoCodes'];
      if (rawPromotions is List) {
        promotionCodes = rawPromotions
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList();
      }
      await localStorage.saveCachedPosFeatureSettings(
        inventoryFeaturesEnabled: inventoryFeaturesEnabled,
        printButtonHidden: printButtonHidden,
        attendanceAuthMode: attendanceAuthMode,
        attendanceWorkdays: attendanceWorkdays,
        attendanceStartTime: attendanceStartTime,
        permissions: ownerPermissions,
      );
    }
  }

  Future<void> _cacheStaffAvatar(String staffId, String avatarPath) async {
    final signedUrl = await supabaseService.fetchStaffAvatarSignedUrl(staffId);
    if (signedUrl == null || signedUrl.isEmpty) return;
    await OfflineImageCache.cacheImage(
      signedUrl,
      cacheKey: OfflineImageCache.staffAvatarCacheKey(avatarPath),
    );
  }

  Future<void> _applyBootstrap(Map<String, dynamic> bootstrap) async {
    await _applyPosSettings(bootstrap['pos']);

    if (bootstrap['menu'] is List) {
      final menu = _syncRows(bootstrap['menu']).map(MenuItem.fromJson).toList();
      await localStorage.saveMenu(menu);
      unawaited(OfflineImageCache.cacheUrls(menu.expand((item) => [
            item.image,
            ...item.addons.map((addon) => addon.image ?? ''),
          ])));
    }
    if (bootstrap['categories'] is List) {
      final categories = (bootstrap['categories'] as List)
          .map((entry) => entry.toString())
          .toList();
      await localStorage.saveCategories(categories);
      final desiredOrder = mergeCategoryOrderPreservingLocal(
        localStorage.getCategoryOrder(),
        categories,
      )
          .where((category) => categories.any(
                (remote) => remote.toLowerCase() == category.toLowerCase(),
              ))
          .toList();
      await localStorage.saveCategoryOrder(desiredOrder);
      if (bootstrap['categoryTypes'] is Map) {
        await localStorage.saveCategoryTypes(
          Map<String, String>.from(bootstrap['categoryTypes'] as Map),
        );
      }
    }
    if (bootstrap['inventory'] is List) {
      final remote = _syncRows(bootstrap['inventory'])
          .map(InventoryItem.fromJson)
          .toList();
      await localStorage.saveInventory(mergeById(
        current: remote,
        updates: localStorage.getPendingInventoryItems(),
        idOf: (item) => item.id,
        deletedIds: localStorage.getPendingInventoryDeletes().toSet(),
      ));
    }
    if (bootstrap['users'] is List) {
      await _applyUsers(_syncRows(bootstrap['users']), replace: true);
    }
    if (bootstrap['restocks'] is List) {
      final remote = _syncRows(bootstrap['restocks']).map((row) {
        row['isSynced'] = true;
        return RestockRecord.fromJson(row);
      }).toList();
      final pending = localStorage.getPendingRestocks();
      await localStorage.saveRestocks(mergeById(
        current: remote,
        updates: pending,
        idOf: (record) => record.id,
      ));
    }
    if (bootstrap['orders'] is List) {
      final remote = _syncRows(bootstrap['orders']).map((row) {
        row['isSynced'] = true;
        return Order.fromJson(row);
      }).toList();
      final mergedOrders = mergeById(
        current: remote,
        updates: localStorage.getPendingOrders(),
        idOf: (order) => order.id,
      );
      _sortOrdersNewestFirst(mergedOrders);
      await localStorage.saveOrders(mergedOrders);
    }
    if (bootstrap['voidRequests'] is List) {
      final remote = _syncRows(bootstrap['voidRequests']).map((row) {
        row['isSynced'] = true;
        return VoidRequest.fromJson(row);
      }).toList();
      await localStorage.saveVoidRequests(mergeById(
        current: remote,
        updates: localStorage.getPendingVoidRequests(),
        idOf: (request) => request.id,
      ));
    }
    if (bootstrap['loginActivity'] is List) {
      final remote = _syncRows(bootstrap['loginActivity']).map((row) {
        row['isSynced'] = true;
        return LoginActivity.fromJson(row);
      }).toList();
      await localStorage.saveLoginActivity(mergeById(
        current: remote,
        updates: localStorage.getPendingLoginActivity(),
        idOf: (activity) => activity.id,
      ));
    }
    await localStorage.saveRecipesData({
      'recipes': bootstrap['recipes'] ?? {},
      'recipeCostings': bootstrap['recipeCostings'] ?? [],
      'costings': bootstrap['costings'] ?? [],
      'usageLogs': bootstrap['usageLogs'] ?? [],
    });
  }

  Future<void> _applyDelta(Map<String, dynamic> delta) async {
    await _applyPosSettings(delta['pos']);

    if (delta['menu'] is List) {
      final updates = _syncRows(delta['menu']).map(MenuItem.fromJson).toList();
      final menu = mergeById(
        current: localStorage.getMenu(),
        updates: updates,
        idOf: (item) => item.id,
        deletedIds: _deletedIds(delta, 'menu'),
      );
      await localStorage.saveMenu(menu);
      unawaited(OfflineImageCache.cacheUrls(updates.expand((item) => [
            item.image,
            ...item.addons.map((addon) => addon.image ?? ''),
          ])));
    }
    if (delta['categories'] is List) {
      final categories = (delta['categories'] as List)
          .map((entry) => entry.toString())
          .toList();
      await localStorage.saveCategories(categories);
      final desiredOrder = mergeCategoryOrderPreservingLocal(
        localStorage.getCategoryOrder(),
        categories,
      )
          .where((category) => categories.any(
                (remote) => remote.toLowerCase() == category.toLowerCase(),
              ))
          .toList();
      await localStorage.saveCategoryOrder(desiredOrder);
      if (delta['categoryTypes'] is Map) {
        await localStorage.saveCategoryTypes(
          Map<String, String>.from(delta['categoryTypes'] as Map),
        );
      }
    }
    if (delta['inventory'] is List) {
      final updates =
          _syncRows(delta['inventory']).map(InventoryItem.fromJson).toList();
      final pendingInventory = localStorage.getPendingInventoryItems();
      await localStorage.saveInventory(mergeById(
        current: localStorage.getInventory(),
        updates: updates,
        idOf: (item) => item.id,
        deletedIds: {
          ..._deletedIds(delta, 'inventory'),
          ...localStorage.getPendingInventoryDeletes(),
        },
        preserveIds: pendingInventory.map((item) => item.id).toSet(),
      ));
    }
    if (delta['users'] is List || _deletedIds(delta, 'users').isNotEmpty) {
      await _applyUsers(
        _syncRows(delta['users']),
        deletedIds: _deletedIds(delta, 'users'),
      );
    }
    if (delta['restocks'] is List ||
        _deletedIds(delta, 'restocks').isNotEmpty) {
      final updates = _syncRows(delta['restocks']).map((row) {
        row['isSynced'] = true;
        return RestockRecord.fromJson(row);
      }).toList();
      final pendingDeleteIds = localStorage.getPendingRestockDeletes().toSet();
      await localStorage.saveRestocks(mergeById(
        current: localStorage.getRestocks(),
        updates: updates,
        idOf: (record) => record.id,
        deletedIds: {
          ..._deletedIds(delta, 'restocks'),
          ...pendingDeleteIds,
        },
        preserveIds: localStorage
            .getPendingRestocks()
            .map((record) => record.id)
            .toSet(),
      ));
    }
    if (delta['orders'] is List || _deletedIds(delta, 'orders').isNotEmpty) {
      final updates = _syncRows(delta['orders']).map((row) {
        row['isSynced'] = true;
        return Order.fromJson(row);
      }).toList();
      final mergedOrders = mergeById(
        current: localStorage.getOrders(),
        updates: updates,
        idOf: (order) => order.id,
        deletedIds: _deletedIds(delta, 'orders'),
        preserveIds:
            localStorage.getPendingOrders().map((order) => order.id).toSet(),
      );
      _sortOrdersNewestFirst(mergedOrders);
      await localStorage.saveOrders(mergedOrders);
    }
    if (delta['voidRequests'] is List ||
        _deletedIds(delta, 'voidRequests').isNotEmpty) {
      final updates = _syncRows(delta['voidRequests']).map((row) {
        row['isSynced'] = true;
        return VoidRequest.fromJson(row);
      }).toList();
      await localStorage.saveVoidRequests(mergeById(
        current: localStorage.getVoidRequests(),
        updates: updates,
        idOf: (request) => request.id,
        deletedIds: _deletedIds(delta, 'voidRequests'),
        preserveIds: localStorage
            .getPendingVoidRequests()
            .map((request) => request.id)
            .toSet(),
      ));
    }
    if (delta['loginActivity'] is List ||
        _deletedIds(delta, 'loginActivity').isNotEmpty) {
      final updates = _syncRows(delta['loginActivity']).map((row) {
        row['isSynced'] = true;
        return LoginActivity.fromJson(row);
      }).toList();
      await localStorage.saveLoginActivity(mergeById(
        current: localStorage.getLoginActivity(),
        updates: updates,
        idOf: (activity) => activity.id,
        deletedIds: _deletedIds(delta, 'loginActivity'),
        preserveIds: localStorage
            .getPendingLoginActivity()
            .map((activity) => activity.id)
            .toSet(),
      ));
    }

    final recipesData = localStorage.getRecipesData();
    if (delta['recipes'] is Map) {
      final recipes = Map<String, dynamic>.from(recipesData['recipes'] is Map
          ? recipesData['recipes'] as Map
          : const {});
      for (final entry
          in Map<String, dynamic>.from(delta['recipes'] as Map).entries) {
        if (entry.value is List && (entry.value as List).isEmpty) {
          recipes.remove(entry.key);
        } else {
          recipes[entry.key] = entry.value;
        }
      }
      recipesData['recipes'] = recipes;
    }
    if (delta['recipeCostings'] is List ||
        _deletedIds(delta, 'recipeCostings').isNotEmpty) {
      final current = _syncRows(recipesData['recipeCostings']);
      final updates = _syncRows(delta['recipeCostings']);
      recipesData['recipeCostings'] = mergeById(
        current: current,
        updates: updates,
        idOf: (row) => row['id']?.toString() ?? '',
        deletedIds: _deletedIds(delta, 'recipeCostings'),
      );
    }
    if (delta['usageLogs'] is List ||
        _deletedIds(delta, 'usageLogs').isNotEmpty) {
      recipesData['usageLogs'] = mergeById(
        current: _syncRows(recipesData['usageLogs']),
        updates: _syncRows(delta['usageLogs']),
        idOf: (row) => row['id']?.toString() ?? '',
        deletedIds: _deletedIds(delta, 'usageLogs'),
      );
    }
    if (delta['costings'] is List) {
      recipesData['costings'] = delta['costings'];
    }
    await localStorage.saveRecipesData(recipesData);
  }

  /// Dynamically calculates ingredient deductions based strictly on Admin recipes, recipeCostings, costings, and addons
  List<Map<String, dynamic>> buildDeductionsForOrder(Order order) {
    return buildDeductionsForItems(order.items);
  }

  List<Map<String, dynamic>> findStockShortfalls(List<OrderItem> items) {
    final requiredByInventoryId = <String, double>{};
    final itemDetails = <String, Map<String, String>>{};
    for (final deduction in buildDeductionsForItems(items)) {
      final id = deduction['inventoryItemId']?.toString() ?? '';
      if (id.isEmpty) continue;
      requiredByInventoryId.update(
        id,
        (amount) => amount + ((deduction['amount'] as num?)?.toDouble() ?? 0),
        ifAbsent: () => (deduction['amount'] as num?)?.toDouble() ?? 0,
      );
      itemDetails[id] = {
        'name': deduction['itemName']?.toString() ?? id,
        'unit': deduction['unit']?.toString() ?? 'pcs',
      };
    }

    final inventoryById = {
      for (final item in localStorage.getInventory()) item.id: item,
    };
    return requiredByInventoryId.entries.where((entry) {
      final stock = inventoryById[entry.key];
      return stock != null && entry.value > stock.stock;
    }).map((entry) {
      final stock = inventoryById[entry.key]!;
      final details = itemDetails[entry.key]!;
      return {
        'itemName': details['name'],
        'required': entry.value,
        'available': stock.stock,
        'unit': details['unit'],
      };
    }).toList();
  }

  List<Map<String, dynamic>> buildDeductionsForItems(List<OrderItem> items) {
    final inventory = localStorage.getInventory();
    final recipesData = localStorage.getRecipesData();
    final menu = localStorage.getMenu();
    return _buildDeductionsForItemsUsingSnapshot(
      items,
      inventory: inventory,
      recipesData: recipesData,
      menu: menu,
    );
  }

  Iterable<Map<String, dynamic>> buildDeductionsForOrders(
    Iterable<Order> orders,
  ) sync* {
    final inventory = localStorage.getInventory();
    final recipesData = localStorage.getRecipesData();
    final menu = localStorage.getMenu();
    final recipeCostings = (recipesData['recipeCostings'] is List)
        ? (recipesData['recipeCostings'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final recipesMap = (recipesData['recipes'] is Map)
        ? Map<String, dynamic>.from(recipesData['recipes'] as Map)
        : <String, dynamic>{};
    final costings = (recipesData['costings'] is List)
        ? (recipesData['costings'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    for (final order in orders) {
      yield* _buildDeductionsForItemsUsingSnapshot(
        order.items,
        inventory: inventory,
        recipesData: recipesData,
        menu: menu,
        recipeCostings: recipeCostings,
        recipesMap: recipesMap,
        costings: costings,
      );
    }
  }

  List<Map<String, dynamic>> _buildDeductionsForItemsUsingSnapshot(
    List<OrderItem> items, {
    required List<InventoryItem> inventory,
    required Map<String, dynamic> recipesData,
    required List<MenuItem> menu,
    List<Map<String, dynamic>>? recipeCostings,
    Map<String, dynamic>? recipesMap,
    List<Map<String, dynamic>>? costings,
  }) {
    final deductions = <Map<String, dynamic>>[];

    final preparedRecipeCostings = recipeCostings ??
        ((recipesData['recipeCostings'] is List)
            ? (recipesData['recipeCostings'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : <Map<String, dynamic>>[]);
    final preparedRecipesMap = recipesMap ??
        ((recipesData['recipes'] is Map)
            ? Map<String, dynamic>.from(recipesData['recipes'] as Map)
            : <String, dynamic>{});
    final preparedCostings = costings ??
        ((recipesData['costings'] is List)
            ? (recipesData['costings'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : <Map<String, dynamic>>[]);

    for (final line in items) {
      final menuItem = menu
          .where((m) =>
              m.id == line.productId ||
              m.name.toLowerCase() == line.name.toLowerCase())
          .firstOrNull;
      final itemName = (menuItem?.name ?? line.name).trim();
      if (menuItem?.inventoryMode == 'none') continue;
      if (menuItem?.inventoryMode == 'stock_only') {
        final selectedSize = line.addons
            .where((addon) =>
                addon.id?.startsWith('size:') == true && addon.qty > 0)
            .firstOrNull;
        final sizeSpec = selectedSize == null
            ? null
            : menuItem?.addons
                .where((addon) =>
                    addon.id == selectedSize.id ||
                    addon.name.trim().toLowerCase() ==
                        selectedSize.name.trim().toLowerCase())
                .firstOrNull;
        final stockId = selectedSize == null
            ? menuItem?.stockInventoryItemId
            : sizeSpec?.inventoryItemId ?? selectedSize.inventoryItemId;
        final stockItem = stockId == null
            ? null
            : inventory.where((item) => item.id == stockId).firstOrNull;
        final usagePerSelection = selectedSize == null
            ? menuItem?.stockUsageAmount ?? 1
            : sizeSpec?.usageAmount ?? selectedSize.usageAmount ?? 1;
        final amount = usagePerSelection * line.qty * (selectedSize?.qty ?? 1);
        if (stockItem != null && amount > 0) {
          deductions.add({
            'inventoryItemId': stockItem.id,
            'name': stockItem.name,
            'amount': amount,
            'unit': stockItem.unit,
          });
        }
        continue;
      }
      var hasConfiguredRecipe = false;

      // 1. Check recipeCostings
      Map<String, dynamic>? matchedCosting;
      for (final rc in preparedRecipeCostings) {
        final menuItems = (rc['menuItems'] is List)
            ? (rc['menuItems'] as List)
                .map((e) => e.toString().trim().toLowerCase())
                .toList()
            : <String>[];
        if (menuItems.contains(itemName.toLowerCase()) ||
            menuItems.contains(line.name.trim().toLowerCase())) {
          matchedCosting = rc;
          break;
        }
      }

      if (matchedCosting != null) {
        final style = line.style ??
            ((menuItem?.styles.length ?? 0) == 1
                ? menuItem!.styles.first
                : null);
        final selectedSize = line.addons
            .where((addon) =>
                addon.id?.startsWith('size:') == true && addon.qty > 0)
            .firstOrNull;
        String sizeKey(String value) =>
            value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]'), '');
        final selectedSizeKey =
            selectedSize == null ? '' : sizeKey(selectedSize.name);
        final configuredCupId = style == 'hot'
            ? matchedCosting['hotCupInventoryItemId']?.toString()
            : style == 'iced'
                ? matchedCosting['icedCupInventoryItemId']?.toString()
                : matchedCosting['otherCupInventoryItemId']?.toString();
        final extraCupIds = matchedCosting['extraCupInventoryItemIds'] is List
            ? (matchedCosting['extraCupInventoryItemIds'] as List)
                .map((id) => id.toString())
                .toSet()
            : <String>{};
        final assignedCupIds = <String>{
          if (configuredCupId != null && configuredCupId.isNotEmpty)
            configuredCupId,
          ...extraCupIds,
        };
        bool matchesSelectedCup(InventoryItem item) {
          final itemStyle = item.inventoryType;
          final styleMatches = style == null ||
              itemStyle == null ||
              !itemStyle.startsWith('cup_') ||
              itemStyle == 'cup_$style';
          final itemSize = sizeKey(item.cupSize ?? item.name);
          return styleMatches && itemSize == selectedSizeKey;
        }

        final sizeCup = selectedSizeKey.isEmpty
            ? null
            : inventory
                    .where((item) =>
                        matchesSelectedCup(item) &&
                        assignedCupIds.contains(item.id))
                    .firstOrNull ??
                inventory
                    .where((item) =>
                        matchesSelectedCup(item) &&
                        (style == null || item.inventoryType == 'cup_$style'))
                    .firstOrNull ??
                inventory.where(matchesSelectedCup).firstOrNull;
        final cupStock = sizeCup ??
            (configuredCupId == null
                ? null
                : inventory
                    .where((item) => item.id == configuredCupId)
                    .firstOrNull);
        final cupId = cupStock?.id ?? configuredCupId;

        final cupRecipesRaw =
            matchedCosting['cupRecipes'] ?? matchedCosting['cup_recipes'];
        final cupRecipes = cupRecipesRaw is Map
            ? Map<String, dynamic>.from(cupRecipesRaw)
            : <String, dynamic>{};
        final selectedCupRecipe = cupId != null && cupRecipes[cupId] is List
            ? cupRecipes[cupId] as List
            : null;
        final hasCupSpecificRecipes = cupRecipes.isNotEmpty;
        final recipeIngredients = cupId != null && hasCupSpecificRecipes
            ? selectedCupRecipe ?? const <dynamic>[]
            : (matchedCosting['ingredients'] is List
                ? matchedCosting['ingredients'] as List
                : const <dynamic>[]);
        hasConfiguredRecipe = recipeIngredients.any((rawIng) =>
            rawIng is Map && ((rawIng['amount'] as num?)?.toDouble() ?? 0) > 0);

        for (final rawIng in recipeIngredients) {
          if (rawIng is Map) {
            final ingId = rawIng['inventoryItemId']?.toString() ?? '';
            final ingName = rawIng['name']?.toString() ?? '';
            final amount = (rawIng['amount'] as num?)?.toDouble() ?? 0.0;
            final unit = rawIng['unit']?.toString() ?? 'pcs';
            if (amount > 0) {
              final stockItem = inventory
                  .where((i) =>
                      i.id == ingId ||
                      i.name.toLowerCase() == ingName.toLowerCase())
                  .firstOrNull;
              if (stockItem != null) {
                deductions.add({
                  'inventoryItemId': stockItem.id,
                  'itemName': stockItem.name,
                  'amount': amount * line.qty,
                  'unit': unit,
                  'orderItemId': line.productId,
                });
              }
            }
          }
        }
        // Cup from recipeCosting
        if (hasConfiguredRecipe && cupId != null && cupId.isNotEmpty) {
          final resolvedCupStock =
              cupStock ?? inventory.where((i) => i.id == cupId).firstOrNull;
          if (resolvedCupStock != null) {
            deductions.add({
              'inventoryItemId': resolvedCupStock.id,
              'itemName': resolvedCupStock.name,
              'amount': 1.0 * line.qty,
              'unit': resolvedCupStock.unit,
              'orderItemId': line.productId,
            });
          }
        }
      } else if (preparedRecipeCostings.isEmpty && menuItem == null) {
        // Once the owner has configured recipe costings, they are authoritative.
        // Known menu items without a current costing must never resurrect a
        // stale legacy recipe. Legacy fallback is only for non-menu orders.
        // 2. Check recipes map
        final recipeList =
            preparedRecipesMap[line.productId] ?? preparedRecipesMap[itemName];
        if (recipeList is List) {
          hasConfiguredRecipe = recipeList.any((rawIng) =>
              rawIng is Map &&
              ((rawIng['amount'] as num?)?.toDouble() ?? 0) > 0);
          for (final rawIng in recipeList) {
            if (rawIng is Map) {
              final ingId = rawIng['inventoryItemId']?.toString() ?? '';
              final ingName = rawIng['name']?.toString() ?? '';
              final amount = (rawIng['amount'] as num?)?.toDouble() ?? 0.0;
              final unit = rawIng['unit']?.toString() ?? 'pcs';
              if (amount > 0) {
                final stockItem = inventory
                    .where((i) =>
                        i.id == ingId ||
                        i.name.toLowerCase() == ingName.toLowerCase())
                    .firstOrNull;
                if (stockItem != null) {
                  deductions.add({
                    'inventoryItemId': stockItem.id,
                    'itemName': stockItem.name,
                    'amount': amount * line.qty,
                    'unit': unit,
                    'orderItemId': line.productId,
                  });
                }
              }
            }
          }
        } else {
          // 3. Check costings
          for (final c in preparedCostings) {
            if ((c['productName']?.toString() ?? '').trim().toLowerCase() ==
                    itemName.toLowerCase() &&
                c['ingredients'] is List) {
              final costingIngredients = c['ingredients'] as List;
              hasConfiguredRecipe = costingIngredients.any((rawIng) =>
                  rawIng is Map &&
                  ((rawIng['amount'] as num?)?.toDouble() ?? 0) > 0);
              for (final rawIng in costingIngredients) {
                if (rawIng is Map) {
                  final ingName = rawIng['name']?.toString() ?? '';
                  final packAmount =
                      (rawIng['amount'] as num?)?.toDouble() ?? 0.0;
                  final outputCups =
                      (rawIng['outputCups'] as num?)?.toDouble() ?? 0.0;
                  final perCup =
                      outputCups > 0 ? (packAmount / outputCups) : packAmount;
                  if (perCup > 0) {
                    final stockItem = inventory
                        .where((i) =>
                            i.name.toLowerCase() == ingName.toLowerCase())
                        .firstOrNull;
                    if (stockItem != null) {
                      deductions.add({
                        'inventoryItemId': stockItem.id,
                        'itemName': stockItem.name,
                        'amount': perCup * line.qty,
                        'unit': rawIng['unit']?.toString() ?? stockItem.unit,
                        'orderItemId': line.productId,
                      });
                    }
                  }
                }
              }
            }
          }
        }
      }

      // 4. Addon inventory deductions configured in Admin
      if (hasConfiguredRecipe) {
        for (final addon in line.addons) {
          if (addon.inventoryItemId != null &&
              addon.inventoryItemId!.isNotEmpty) {
            final stockItem = inventory
                .where((i) => i.id == addon.inventoryItemId)
                .firstOrNull;
            if (stockItem != null) {
              final usagePerAddon =
                  (addon.usageAmount != null && addon.usageAmount! > 0)
                      ? addon.usageAmount!
                      : (stockItem.cupUsageAmount != null &&
                              stockItem.cupUsageAmount! > 0
                          ? stockItem.cupUsageAmount!
                          : 1.0);
              deductions.add({
                'inventoryItemId': stockItem.id,
                'itemName': stockItem.name,
                'amount': usagePerAddon * addon.qty * line.qty,
                'unit': addon.usageUnit ?? stockItem.unit,
                'orderItemId': line.productId,
              });
            }
          }
        }
      }
    }

    return deductions;
  }
}
