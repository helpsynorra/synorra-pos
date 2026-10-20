import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'local_storage_service.dart';
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
  final LocalStorageService localStorage;
  final SupabaseService supabaseService;

  SyncStatus status = SyncStatus.idle;
  bool isOnline = true;
  bool inventoryFeaturesEnabled = true;
  bool printButtonHidden = false;
  final Map<String, bool> ownerPermissions = {
    'stockInventory': true,
    'restockInventory': true,
    'connectLabels': true,
    'connectReceipt': true,
    'printButton': true,
    'customerReceipt': true,
    'cupLabels': true,
    'dineIn': true,
    'takeOut': true,
    'promotionDiscount': false,
    'promotionsEnabled': false,
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
  });

  void start() {
    updatePendingCount();

    // Listen to network changes
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final connected = results.any((r) => r != ConnectivityResult.none);
      isOnline = connected;
      if (connected) {
        syncAll();
      } else {
        status = SyncStatus.offline;
        notifyListeners();
      }
    });

    // Real-time auto-sync every 5 seconds when online
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (isOnline && status != SyncStatus.syncing) {
        syncAll();
      }
    });

    // Initial sync immediately
    syncAll();
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

  /// Full bidirectional real-time synchronization with the centralized Admin database
  Future<void> syncAll() async {
    if (_activeSyncFuture != null) {
      return _activeSyncFuture!;
    }
    _activeSyncFuture = _performSync();
    try {
      await _activeSyncFuture;
    } finally {
      _activeSyncFuture = null;
    }
  }

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
      // 1. Push any pending offline queues FIRST so newly created POS actions are persisted before pulling
      final pendingPunches = localStorage.getPendingLoginActivity();
      for (final punch in pendingPunches) {
        final ok = await supabaseService.pushLoginActivity(punch);
        if (ok) {
          punch.isSynced = true;
          await localStorage.removePendingLoginActivity(punch.id);
        }
      }

      final pendingOrders = localStorage.getPendingOrders();
      for (final order in pendingOrders) {
        String? managerUsername;
        String? managerPassword;
        if (order.voided) {
          final manager = localStorage
              .getStaff()
              .where((staff) => staff.id == order.voidedBy)
              .firstOrNull;
          if (manager == null) {
            debugPrint(
              'Pending void sync skipped (${order.id}): manager account is not cached.',
            );
            continue;
          }
          managerPassword =
              await localStorage.getOfflineStaffCredential(manager.id);
          if (managerPassword == null || managerPassword.isEmpty) {
            debugPrint(
              'Pending void sync skipped (${order.id}): secure manager credential is unavailable.',
            );
            continue;
          }
          managerUsername = manager.username;
        }

        final deductions = order.voided
            ? const <Map<String, dynamic>>[]
            : buildDeductionsForOrder(order);
        final result = await supabaseService.pushOrderAtomic(
          order,
          deductions,
          managerUsername: managerUsername,
          managerPassword: managerPassword,
        );
        if (result['ok'] == true) {
          order.isSynced = true;
          if (result['ticketNo'] != null &&
              result['ticketNo'].toString().isNotEmpty) {
            order.ticketNo = result['ticketNo'].toString();
          }
          await localStorage.addOrder(order);
          await localStorage.removePendingOrder(order.id);
        } else {
          debugPrint(
            'Pending order sync failed (${order.id}): ${result['error'] ?? 'Unknown server error'}',
          );
        }
      }

      final pendingRestocks = localStorage.getPendingRestocks();
      for (final restock in pendingRestocks) {
        final ok = await supabaseService.pushRestockAtomic(restock);
        if (ok) {
          restock.isSynced = true;
          await localStorage.removePendingRestock(restock.id);
        }
      }

      final pendingRestockDeletes = localStorage.getPendingRestockDeletes();
      for (final restockId in pendingRestockDeletes) {
        final ok = await supabaseService.deleteRestockAtomic(restockId);
        if (ok) await localStorage.removePendingRestockDelete(restockId);
      }

      final pendingVoids = localStorage.getPendingVoidRequests();
      for (final voidReq in pendingVoids) {
        final ok = await supabaseService.pushVoidRequest(voidReq);
        if (ok) {
          voidReq.isSynced = true;
          await localStorage.removePendingVoidRequest(voidReq.id);
        }
      }

      // 2. Pull authoritative centralized store from Admin API (/api/sync)
      final fullStore = await supabaseService.fetchFullStore();
      if (fullStore != null) {
        final posState = fullStore['pos'];
        if (posState is Map) {
          inventoryFeaturesEnabled =
              posState['inventoryFeaturesEnabled'] != false;
          printButtonHidden = posState['printButtonHidden'] == true;
        }
        if (fullStore['menu'] is List) {
          final freshMenu = (fullStore['menu'] as List)
              .whereType<Map>()
              .map((e) => MenuItem.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          await localStorage.saveMenu(freshMenu);
        }

        if (fullStore['categories'] is List) {
          final freshCategories = (fullStore['categories'] as List)
              .map((e) => e.toString())
              .toList();
          await localStorage.saveCategories(freshCategories);
        }

        if (fullStore['inventory'] is List) {
          final freshInventory = (fullStore['inventory'] as List)
              .whereType<Map>()
              .map((e) => InventoryItem.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          await localStorage.saveInventory(freshInventory);
        }

        if (fullStore['users'] is List) {
          final activeStaffId = localStorage.getActiveStaffId();
          Map<String, dynamic>? activeUser;
          for (final entry in (fullStore['users'] as List).whereType<Map>()) {
            final user = Map<String, dynamic>.from(entry);
            if (user['id']?.toString() == activeStaffId) {
              activeUser = user;
              break;
            }
          }
          final permissions = activeUser?['permissions'];
          promotionCodes = [];
          for (final key in ownerPermissions.keys.toList()) {
            ownerPermissions[key] = true;
          }
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
              promotionCodes = rawPromotions.whereType<Map>()
                  .map((entry) => Map<String, dynamic>.from(entry))
                  .toList();
            }
          }
          final freshStaff = (fullStore['users'] as List)
              .whereType<Map>()
              .map((e) => StaffUser.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          await localStorage.saveStaff(freshStaff);
        }

        if (fullStore['restocks'] is List) {
          final freshRestocks =
              (fullStore['restocks'] as List).whereType<Map>().map((e) {
            final map = Map<String, dynamic>.from(e);
            map['isSynced'] = true;
            return RestockRecord.fromJson(map);
          }).toList();
          await localStorage.saveRestocks(freshRestocks);
        }

        if (fullStore['orders'] is List) {
          final freshOrders =
              (fullStore['orders'] as List).whereType<Map>().map((e) {
            final map = Map<String, dynamic>.from(e);
            map['isSynced'] = true;
            return Order.fromJson(map);
          }).toList();
          await localStorage.saveOrders(freshOrders);
        }

        if (fullStore['voidRequests'] is List) {
          final freshVoids =
              (fullStore['voidRequests'] as List).whereType<Map>().map((e) {
            final map = Map<String, dynamic>.from(e);
            map['isSynced'] = true;
            return VoidRequest.fromJson(map);
          }).toList();
          await localStorage.saveVoidRequests(freshVoids);
        }

        if (fullStore['loginActivity'] is List) {
          final freshLogs =
              (fullStore['loginActivity'] as List).whereType<Map>().map((e) {
            final map = Map<String, dynamic>.from(e);
            map['isSynced'] = true;
            return LoginActivity.fromJson(map);
          }).toList();
          await localStorage.saveLoginActivity(freshLogs);
        }

        await localStorage.saveRecipesData({
          'recipes': fullStore['recipes'] ?? {},
          'recipeCostings': fullStore['recipeCostings'] ?? [],
          'costings': fullStore['costings'] ?? [],
          'usageLogs': fullStore['usageLogs'] ?? [],
        });

        status = SyncStatus.success;
        isOnline = true;
        lastSyncTime = DateTime.now();
        onSyncCompleted?.call();
      } else {
        status = SyncStatus.error;
        lastError = 'Unable to sync with the authenticated POS server.';
      }
    } catch (e) {
      debugPrint('Sync warning: $e');
      status = SyncStatus.error;
      lastError = e.toString();
    } finally {
      updatePendingCount();
    }
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
    final deductions = <Map<String, dynamic>>[];
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

    for (final line in items) {
      final menuItem = menu
          .where((m) =>
              m.id == line.productId ||
              m.name.toLowerCase() == line.name.toLowerCase())
          .firstOrNull;
      final itemName = (menuItem?.name ?? line.name).trim();

      // 1. Check recipeCostings
      Map<String, dynamic>? matchedCosting;
      for (final rc in recipeCostings) {
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
        if (matchedCosting['ingredients'] is List) {
          for (final rawIng in (matchedCosting['ingredients'] as List)) {
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
        }
        // Cup from recipeCosting
        final cupId = line.style == 'hot'
            ? matchedCosting['hotCupInventoryItemId']?.toString()
            : line.style == 'iced'
                ? matchedCosting['icedCupInventoryItemId']?.toString()
                : matchedCosting['otherCupInventoryItemId']?.toString();
        if (cupId != null && cupId.isNotEmpty) {
          final cupStock = inventory.where((i) => i.id == cupId).firstOrNull;
          if (cupStock != null) {
            deductions.add({
              'inventoryItemId': cupStock.id,
              'itemName': cupStock.name,
              'amount': 1.0 * line.qty,
              'unit': cupStock.unit,
              'orderItemId': line.productId,
            });
          }
        }
      } else {
        // 2. Check recipes map
        final recipeList = recipesMap[line.productId] ?? recipesMap[itemName];
        if (recipeList is List) {
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
          for (final c in costings) {
            if ((c['productName']?.toString() ?? '').trim().toLowerCase() ==
                    itemName.toLowerCase() &&
                c['ingredients'] is List) {
              for (final rawIng in (c['ingredients'] as List)) {
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
      for (final addon in line.addons) {
        if (addon.inventoryItemId != null &&
            addon.inventoryItemId!.isNotEmpty) {
          final stockItem =
              inventory.where((i) => i.id == addon.inventoryItemId).firstOrNull;
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

    return deductions;
  }
}
