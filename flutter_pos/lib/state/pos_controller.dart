import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/menu_item.dart';
import '../models/order_item.dart';
import '../models/order.dart';
import '../models/inventory_item.dart';
import '../models/void_request.dart';
import '../models/restock_record.dart';
import '../manila_time.dart';
import '../models/staff_user.dart';
import '../models/login_activity.dart';
import '../services/local_storage_service.dart';
import '../services/supabase_service.dart';
import '../services/sync_service.dart';

enum RestockDeleteResult { deleted, queued, failed }

class PosController extends ChangeNotifier {
  final LocalStorageService localStorage;
  final SupabaseService supabaseService;
  final SyncService syncService;

  StaffUser? currentUser;
  String currentBaristaName = 'Barista';
  String? currentBaristaUserId;
  List<StaffUser> onShiftBaristas = [];
  bool isPosOpen = false;
  bool _staffLogoutInProgress = false;
  String? _staffLogoutRecordedFor;

  // Strictly dynamic lists synced from the Admin database (NEVER hardcoded)
  List<MenuItem> menu = [];
  List<String> categories = ['All'];
  List<InventoryItem> inventory = [];
  List<Order> orders = [];
  List<VoidRequest> voidRequests = [];
  List<RestockRecord> restocks = [];
  List<StaffUser> staffUsers = [];
  List<LoginActivity> shiftLogs = [];
  Map<String, dynamic> recipesData = {};
  String? pendingCartVoidRequestId;

  bool get isVoidRequestPending => pendingCartVoidRequestId != null;

  // Filtering
  String selectedCategory = 'All';

  // Cart
  List<OrderItem> cart = [];
  String paymentMethod = 'cash'; // 'cash', 'gcash', 'maya'
  double tenderedAmount = 0.0;
  String serviceMode = 'dine-in';
  String? promoId;
  String? promoLabel;
  int? promoItemIndex;
  int? promoItemQty;
  double discountAmount = 0.0;

  Order? lastCompletedOrder;
  bool isProcessing = false;

  PosController({
    required this.localStorage,
    required this.supabaseService,
    required this.syncService,
  }) {
    syncService.onSyncCompleted = _refreshFromLocalStorage;
  }

  void _refreshFromLocalStorage() {
    menu = localStorage.getMenu();
    final syncedCategories = localStorage.getCategories();
    final savedOrder = localStorage.getCategoryOrder();
    final availableCategories = syncedCategories.toSet();
    categories = [
      'All',
      ...savedOrder.where(
        (category) =>
            category != 'All' && availableCategories.remove(category),
      ),
      ...syncedCategories.where(
        (category) =>
            category != 'All' && availableCategories.remove(category),
      ),
    ];
    if (!categories.contains(selectedCategory)) {
      selectedCategory = 'All';
    }
    inventory = localStorage.getInventory();
    orders = localStorage.getOrders();
    staffUsers = localStorage.getStaff();
    voidRequests = localStorage.getVoidRequests();
    final pendingRequest = voidRequests
        .where((request) => request.id == pendingCartVoidRequestId)
        .firstOrNull;
    if (pendingRequest?.status == 'approved') {
      if (pendingRequest!.orderId == null) {
        clearCart();
        paymentMethod = 'cash';
      }
      pendingCartVoidRequestId = null;
    }
    restocks = localStorage.getRestocks();
    shiftLogs = localStorage.getLoginActivity();
    _restoreOnShiftBarista();
    recipesData = localStorage.getRecipesData();
    _refreshPromotionDiscount();
    notifyListeners();
  }

  void _restoreOnShiftBarista() {
    final active = LoginActivity.openBaristaShifts(shiftLogs);
    onShiftBaristas = active
        .map((event) =>
            staffUsers.where((staff) => staff.id == event.userId).firstOrNull)
        .whereType<StaffUser>()
        .toList();
    final onShift = active.firstOrNull;
    currentBaristaName = onShift?.name ?? 'Barista';
    currentBaristaUserId = onShift?.userId;
  }

  void _restoreActiveStaff() {
    final staffId = localStorage.getActiveStaffId();
    if (staffId == null) {
      supabaseService.setPosApiToken(null);
      return;
    }
    final staff = staffUsers.where((user) => user.id == staffId).firstOrNull ??
        localStorage.getActiveStaffProfile();
    if (staff == null || !staff.canLoginToPos) {
      supabaseService.setPosApiToken(null);
      return;
    }
    supabaseService.setPosApiToken(localStorage.getPosApiToken());
    currentUser = staff;
  }

  Future<void> clearActiveSession() async {
    await localStorage.clearActiveStaffId();
    supabaseService.setPosApiToken(null);
    currentUser = null;
    notifyListeners();
  }

  Future<void> recordStaffSessionEvent(StaffUser staff, String type) async {
    if (type != 'login' && type != 'logout') {
      return;
    }

    if (staff.canAccessBaristaShift) {
      await punchShift(staff, type);
      return;
    }
    if (!staff.canLoginToPos) return;

    if (type == 'login') {
      _staffLogoutRecordedFor = null;
      await _recordLoginActivity(
        staff,
        type,
        idPrefix: staff.canUsePos ? 'cashier' : 'staff',
      );
      return;
    }

    if (_staffLogoutInProgress || _staffLogoutRecordedFor == staff.id) {
      return;
    }
    _staffLogoutInProgress = true;
    _staffLogoutRecordedFor = staff.id;
    try {
      await _recordLoginActivity(staff, type, idPrefix: 'staff');
    } catch (_) {
      _staffLogoutRecordedFor = null;
      rethrow;
    } finally {
      _staffLogoutInProgress = false;
    }
  }

  Future<void> init() async {
    isPosOpen = localStorage.getPosIsOpen();
    _restoreActiveCheckout();

    // Load cached Admin state (no hardcoded fallback seeds)
    _refreshFromLocalStorage();
    _restoreActiveStaff();

    // Startup sync starts after the first UI frame.
  }

  void _restoreActiveCheckout() {
    final saved = localStorage.getActiveCheckout();
    if (saved == null) return;

    try {
      final rawItems = saved['items'];
      if (rawItems is List) {
        cart = rawItems
            .whereType<Map>()
            .map((item) => OrderItem.fromJson(Map<String, dynamic>.from(item)))
            .toList();
      }
      final method = saved['paymentMethod'];
      if (method == 'cash' || method == 'gcash' || method == 'maya') {
        paymentMethod = method as String;
      }
      tenderedAmount = (saved['tenderedAmount'] as num?)?.toDouble() ?? 0;
      serviceMode = saved['serviceMode'] == 'take-out' ? 'take-out' : 'dine-in';
      discountAmount = (saved['discountAmount'] as num?)?.toDouble() ?? 0;
      if (paymentMethod == 'cash' && tenderedAmount == 0 && cart.isNotEmpty) {
        tenderedAmount = total;
      }
      promoId = saved['promoId'] as String?;
      promoLabel = saved['promoLabel'] as String?;
      promoItemIndex = (saved['promoItemIndex'] as num?)?.toInt();
      promoItemQty = (saved['promoItemQty'] as num?)?.toInt() ?? (promoItemIndex == null ? null : 1);
      if (promoLabel != null) {
        paymentMethod = 'gcash';
        tenderedAmount = total;
      }
      pendingCartVoidRequestId = saved['pendingVoidRequestId'] as String?;
      if (cart.isEmpty) unawaited(localStorage.clearActiveCheckout());
    } catch (_) {
      cart = [];
      paymentMethod = 'cash';
      tenderedAmount = 0;
      discountAmount = 0;
      promoId = null;
      promoLabel = null;
      promoItemIndex = null;
      promoItemQty = null;
      pendingCartVoidRequestId = null;
      unawaited(localStorage.clearActiveCheckout());
    }
  }

  void _persistActiveCheckout() {
    unawaited(
      localStorage.saveActiveCheckout(
        items: List<OrderItem>.from(cart),
        paymentMethod: paymentMethod,
        tenderedAmount: tenderedAmount,
        serviceMode: serviceMode,
        discountAmount: discountAmount,
        promoId: promoId,
        promoLabel: promoLabel,
        promoItemIndex: promoItemIndex,
        promoItemQty: promoItemQty,
        pendingVoidRequestId: pendingCartVoidRequestId,
      ),
    );
  }

  // --- Date Range Bounds Helper (Matches Admin Panel phPeriodBounds) ---
  bool _isInRange(String isoOrDateStr, String range, DateTime? customDate) {
    final anchor = customDate == null
        ? ManilaTime.today()
        : DateTime.utc(customDate.year, customDate.month, customDate.day);
    return ManilaTime.matchesRange(isoOrDateStr, range, anchor);
  }

  bool isCupInventoryItem(InventoryItem item) {
    final lower = item.name.trim().toLowerCase();
    if (lower.contains('cup') ||
        lower.contains('lid') ||
        lower.contains('straw')) {
      return true;
    }
    final recipeCostings = (recipesData['recipeCostings'] is List)
        ? (recipesData['recipeCostings'] as List).whereType<Map>()
        : const <Map>[];
    for (final rc in recipeCostings) {
      if (rc['hotCupInventoryItemId'] == item.id ||
          rc['icedCupInventoryItemId'] == item.id ||
          rc['otherCupInventoryItemId'] == item.id) {
        return true;
      }
    }
    return false;
  }

  double getTotalCupsUsed({String range = 'Today', DateTime? selectedDate}) {
    double total = 0.0;
    for (final item in inventory) {
      if (isCupInventoryItem(item)) {
        final ledger =
            getStockLedger(item, range: range, selectedDate: selectedDate);
        total += ledger['usedPerUnit'] ?? 0.0;
      }
    }
    return total;
  }

  // --- Stock Ledger Calculation (Matches Admin SalePurchaseTransactions.tsx 100%) ---
  Map<String, double> getStockLedger(
    InventoryItem item, {
    String range = 'Today',
    DateTime? selectedDate,
  }) {
    final itemRestocks = restocks.where((r) =>
        (r.inventoryItemId != null && r.inventoryItemId == item.id) ||
        r.itemName.trim().toLowerCase() == item.name.trim().toLowerCase());

    double totalRestockedInRange = 0;
    for (final r in itemRestocks) {
      if (_isInRange(r.date, range, selectedDate)) {
        totalRestockedInRange += r.quantityAdded;
      }
    }

    double totalUsedInRange = 0;
    final usageLogs = (recipesData['usageLogs'] is List)
        ? (recipesData['usageLogs'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    final loggedOrderIds = <String>{};
    for (final u in usageLogs) {
      final oid = u['orderId']?.toString() ?? '';
      if (oid.isNotEmpty) loggedOrderIds.add(oid);
      final uItemId = u['inventoryItemId']?.toString() ?? '';
      final uItemName = (u['itemName']?.toString() ?? '').trim().toLowerCase();
      final matches = (uItemId.isNotEmpty && uItemId == item.id) ||
          uItemName == item.name.trim().toLowerCase();
      if (matches &&
          _isInRange(u['date']?.toString() ?? '', range, selectedDate)) {
        totalUsedInRange += (u['usedAmount'] as num?)?.toDouble() ?? 0.0;
      }
    }

    for (final order in orders) {
      if (order.voided || loggedOrderIds.contains(order.id)) continue;
      if (!_isInRange(order.createdAt, range, selectedDate)) continue;
      final deductions = syncService.buildDeductionsForOrder(order);
      for (final d in deductions) {
        if (d['inventoryItemId'] == item.id ||
            (d['itemName']?.toString() ?? '').trim().toLowerCase() ==
                item.name.trim().toLowerCase()) {
          totalUsedInRange += (d['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }

    final double pieceSize =
        (item.purchaseUnitSize != null && item.purchaseUnitSize! > 0)
            ? item.purchaseUnitSize!
            : 1.0;
    final double remainingBase = item.stock;
    final double openingBase =
        (remainingBase - totalRestockedInRange + totalUsedInRange)
            .clamp(0.0, double.infinity);

    final double openingPcs = openingBase / pieceSize;
    final double restockedPcs = totalRestockedInRange / pieceSize;
    final double usedPcs =
        (item.purchaseUnitSize != null && item.purchaseUnitSize! > 0)
            ? (totalUsedInRange / item.purchaseUnitSize!)
            : -1.0;
    final double remainingPcs =
        (remainingBase / pieceSize).clamp(0.0, double.infinity);

    // Exact Cups Left calculation from Admin (configuredCupsLeft or cupsMake if unit != 'pcs')
    double? cupsLeft;
    if (item.unit.trim().toLowerCase() != 'pcs') {
      if (item.cupUsageAmount != null && item.cupUsageAmount! > 0) {
        cupsLeft = remainingBase / item.cupUsageAmount!;
      } else if (item.cupsMake != null && item.cupsMake! > 0) {
        cupsLeft = item.cupsMake!;
      }
    }

    return {
      'openingPcs': openingPcs,
      'restockedPcs': restockedPcs,
      'usedPerUnit': totalUsedInRange,
      'usedPcs': usedPcs,
      'remainingPcs': remainingPcs,
      'cupsLeft': cupsLeft ?? -1.0,
    };
  }

  // --- Filtered Menu ---
  List<MenuItem> get filteredMenu {
    return menu.where((item) {
      if (!item.available) return false;
      if (selectedCategory != 'All' &&
          item.category.trim().toLowerCase() !=
              selectedCategory.trim().toLowerCase()) {
        return false;
      }
      return true;
    }).toList();
  }

  void setCategory(String category) {
    selectedCategory = category;
    notifyListeners();
  }

  void reorderCategories(int oldIndex, int newIndex) {
    if (oldIndex == 0 || newIndex == 0 || oldIndex == newIndex) return;
    final reordered = List<String>.of(categories);
    if (newIndex > oldIndex) newIndex--;
    final category = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, category);
    categories = reordered;
    unawaited(localStorage.saveCategoryOrder(categories));
    notifyListeners();
  }

  // --- Cart Management ---
  double get subtotal => cart.fold(0.0, (sum, item) => sum + item.lineTotal);
  double get total =>
      (subtotal - discountAmount) > 0 ? (subtotal - discountAmount) : 0.0;

  String? applyPromotionCode(String rawCode, {int? itemIndex, int? itemQty}) {
    final code = rawCode.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (!syncService.hasPermission('promotionsEnabled') ||
        !syncService.hasPermission('promotionDiscount')) {
      return 'Promotions are not enabled for this Owner.';
    }
    if (!RegExp(r'^(?:[A-Z0-9]{6}|[A-Z0-9]{1,16}-[A-Z0-9]{6})$').hasMatch(code)) {
      return 'Invalid promo voucher.';
    }
    final promo = syncService.promotionCodes.where(
      (entry) => entry['code']?.toString().trim().toUpperCase() == code,
    ).firstOrNull;
    if (promo == null || code.isEmpty) return 'Invalid promo voucher.';
    if (_isPromotionRedeemed(promo)) return 'Promo voucher already used.';
    final value = (promo['discountValue'] as num?)?.toDouble() ?? 0;
    final isFreeItem = promo['discountType'] == 'item';
    final freeItemQty = value.round().clamp(1, 99).toInt();
    if (isFreeItem && (itemIndex == null || itemIndex < 0 || itemIndex >= cart.length || itemQty != freeItemQty || itemQty! > cart[itemIndex].qty)) {
      return 'Choose an item with quantity $freeItemQty or more.';
    }
    final amount = isFreeItem
        ? (cart[itemIndex!].unitPrice * itemQty!).roundToDouble()
        : promo['discountType'] == 'amount'
            ? value
            : subtotal * value / 100;
    if (!isFreeItem && (amount <= 0 || subtotal <= 0)) {
      return 'Add items before applying a promotion.';
    }
    promoId = code;
    promoLabel = code;
    promoItemIndex = isFreeItem ? itemIndex : null;
    promoItemQty = isFreeItem ? itemQty : null;
    discountAmount = amount.clamp(0, subtotal).roundToDouble();
    paymentMethod = 'gcash';
    tenderedAmount = total;
    _persistActiveCheckout();
    notifyListeners();
    return null;
  }

  void _refreshPromotionDiscount() {
    final code = promoId?.trim().toUpperCase();
    if (code == null) return;
    final promo = syncService.promotionCodes.where(
      (entry) => entry['code']?.toString().trim().toUpperCase() == code,
    ).firstOrNull;
    if (promo == null ||
        _isPromotionRedeemed(promo) ||
        !syncService.hasPermission('promotionsEnabled') ||
        !syncService.hasPermission('promotionDiscount')) {
      promoId = null;
      promoLabel = null;
      discountAmount = 0;
      return;
    }
    paymentMethod = 'gcash';
    tenderedAmount = total;
    if (promo['discountType'] == 'item') {
      if (promoItemIndex == null || promoItemIndex! < 0 || promoItemIndex! >= cart.length || promoItemQty == null || promoItemQty! > cart[promoItemIndex!].qty) {
        clearPromotion();
        return;
      }
      discountAmount = (cart[promoItemIndex!].unitPrice * promoItemQty!).roundToDouble();
      return;
    }
    final value = (promo['discountValue'] as num?)?.toDouble() ?? 0;
    final amount = promo['discountType'] == 'amount' ? value : subtotal * value / 100;
    discountAmount = amount.clamp(0, subtotal).roundToDouble();
  }

  bool _isPromotionRedeemed(Map<String, dynamic> promo) =>
      promo['redeemedAt'] != null || promo['redeemed_at'] != null;

  void clearPromotion() {
    final previousTotal = total;
    promoId = null;
    promoLabel = null;
    promoItemIndex = null;
    promoItemQty = null;
    discountAmount = 0;
    if (paymentMethod != 'cash' || tenderedAmount == 0 || tenderedAmount == previousTotal) {
      tenderedAmount = total;
    }
    _persistActiveCheckout();
    notifyListeners();
  }
  double get change => paymentMethod == 'cash' && tenderedAmount >= total
      ? (tenderedAmount - total)
      : 0.0;

  void addToCart(MenuItem product,
      {String? style,
      List<OrderAddonSelection> addons = const [],
      int qty = 1}) {
    if (isVoidRequestPending) return;
    final previousTotal = total;

    final existingIndex = cart.indexWhere((line) {
      if (line.productId != product.id) return false;
      if (line.style != style) return false;
      if (line.addons.length != addons.length) return false;
      for (int i = 0; i < addons.length; i++) {
        if (line.addons[i].name != addons[i].name ||
            line.addons[i].qty != addons[i].qty) {
          return false;
        }
      }
      return true;
    });

    if (existingIndex >= 0) {
      cart[existingIndex].qty += qty;
    } else {
      cart.add(OrderItem(
        productId: product.id,
        name: product.name,
        price: product.price,
        qty: qty,
        style: style,
        addons: addons,
        category: product.category,
      ));
    }
    _refreshPromotionDiscount();
    if (paymentMethod != 'cash' ||
        tenderedAmount == 0 ||
        tenderedAmount == previousTotal) {
      tenderedAmount = total;
    }
    _persistActiveCheckout();
    notifyListeners();
  }

  void updateCartQty(int index, int newQty) {
    if (index >= 0 && index < cart.length) {
      final previousTotal = total;
      if (newQty <= 0) {
        if (promoItemIndex == index) {
          clearPromotion();
        } else if (promoItemIndex != null && promoItemIndex! > index) {
          promoItemIndex = promoItemIndex! - 1;
        }
        cart.removeAt(index);
      } else {
        cart[index].qty = newQty;
      }
      _refreshPromotionDiscount();
      if (paymentMethod != 'cash' ||
          tenderedAmount == 0 ||
          tenderedAmount == previousTotal) {
        tenderedAmount = total;
      }
      _persistActiveCheckout();
      notifyListeners();
    }
  }

  void removeFromCart(int index) {
    if (index >= 0 && index < cart.length) {
      if (promoItemIndex == index) {
        clearPromotion();
      } else if (promoItemIndex != null && promoItemIndex! > index) {
        promoItemIndex = promoItemIndex! - 1;
      }
      cart.removeAt(index);
      _refreshPromotionDiscount();
      if (paymentMethod != 'cash') {
        tenderedAmount = total;
      }
      _persistActiveCheckout();
      notifyListeners();
    }
  }

  void clearCart() {
    cart.clear();
    tenderedAmount = 0.0;
    discountAmount = 0.0;
    promoId = null;
    promoLabel = null;
    promoItemIndex = null;
    promoItemQty = null;
    _persistActiveCheckout();
    notifyListeners();
  }

  void setPaymentMethod(String method) {
    if (promoLabel != null && method != 'gcash') return;
    paymentMethod = method;
    if (method != 'cash') {
      tenderedAmount = total;
    }
    _persistActiveCheckout();
    notifyListeners();
  }

  void setTenderedAmount(double amount, {bool notify = true}) {
    tenderedAmount = amount;
    _persistActiveCheckout();
    if (notify) notifyListeners();
  }

  void setServiceMode(String mode) {
    serviceMode = mode == 'take-out' ? 'take-out' : 'dine-in';
    _persistActiveCheckout();
    notifyListeners();
  }

  // --- Order Checkout ---
  Future<Map<String, dynamic>> proceedOrder() async {
    if (isVoidRequestPending) {
      return {'ok': false, 'error': 'Checkout is waiting for Admin approval.'};
    }
    if (cart.isEmpty) {
      return {'ok': false, 'error': 'Cart is empty'};
    }
    if (paymentMethod == 'cash' && tenderedAmount < total) {
      return {'ok': false, 'error': 'Cash tendered is insufficient'};
    }

    isProcessing = true;
    notifyListeners();

    try {
      final now = ManilaTime.now();
      final createdAt = ManilaTime.utcIsoFromManilaWallTime(now);
      final orderId = 'ord-${now.millisecondsSinceEpoch}';

      final existingTodayCount = orders.where((o) {
        final d = ManilaTime.parse(o.createdAt);
        return d != null &&
            d.year == now.year &&
            d.month == now.month &&
            d.day == now.day;
      }).length;
      final localTicketNo =
          '#${(existingTodayCount + 1).toString().padLeft(3, '0')}';

      final order = Order(
        id: orderId,
        createdAt: createdAt,
        baristaName: currentUser?.name ?? 'Owner',
        baristaUserId: currentUser?.id,
        items: List.from(cart),
        subtotal: subtotal,
        discount: discountAmount,
        promoLabel: promoLabel,
        promoItemIndex: promoItemIndex,
        promoItemQty: promoItemQty,
        total: total,
        paymentMethod: paymentMethod,
        serviceMode: serviceMode,
        ticketNo: localTicketNo,
        paid: paymentMethod == 'cash' ? tenderedAmount : total,
        change: change,
        voided: false,
        isSynced: false,
      );

      final deductions = syncService.buildDeductionsForOrder(order);

      // Push immediately to centralized database
      final hasPosApiToken = syncService.isOnline &&
          await syncService.ensurePosApiToken(forceRefresh: true);
      final pushRes = !syncService.isOnline || !hasPosApiToken
          ? {
              'ok': false,
              'error': !hasPosApiToken
                  ? 'POS session required to sync this order.'
                  : 'Device is offline.',
              'retryable': !syncService.isOnline,
            }
          : await supabaseService.pushOrderAtomic(order, deductions);
      final authRequired = !hasPosApiToken ||
          pushRes['error']?.toString().contains('POS session expired.') == true;
      final shouldQueueForRetry =
          !syncService.isOnline || authRequired || pushRes['retryable'] == true;
      if (pushRes['ok'] != true && !shouldQueueForRetry) {
        isProcessing = false;
        notifyListeners();
        return {
          'ok': false,
          'error': pushRes['error']?.toString() ??
              'The server did not save this order. Please retry.',
        };
      }
      if (pushRes['ok'] == true) {
        order.isSynced = true;
        if (pushRes['ticketNo'] != null &&
            pushRes['ticketNo'].toString().isNotEmpty) {
          order.ticketNo = pushRes['ticketNo'].toString();
        }
      }

      await localStorage.addOrder(order);
      orders.insert(0, order);
      lastCompletedOrder = order;

      // Deduct inventory locally based on Admin recipe deductions
      for (final d in deductions) {
        final stockItem =
            inventory.where((i) => i.id == d['inventoryItemId']).firstOrNull;
        final amount = (d['amount'] as num?)?.toDouble() ?? 0.0;
        if (stockItem != null && amount > 0) {
          stockItem.stock =
              (stockItem.stock - amount).clamp(0.0, double.infinity);
        }
      }
      await localStorage.saveInventory(inventory);

      clearCart();
      syncService.updatePendingCount();
      // Refresh full state from Admin backend
      if (pushRes['ok'] == true) syncService.syncAll();

      isProcessing = false;
      notifyListeners();
      return {
        'ok': true,
        'order': order,
        'synced': pushRes['ok'] == true,
        'networkFailure': !syncService.isOnline || pushRes['retryable'] == true,
        if (pushRes['ok'] != true)
          'syncError': pushRes['error']?.toString() ?? 'Unknown server error',
      };
    } catch (e) {
      isProcessing = false;
      notifyListeners();
      return {'ok': false, 'error': e.toString()};
    }
  }

  // --- Void Order Workflow ---
  Future<Map<String, dynamic>> voidOrder(
    String orderId,
    String reason,
    String managerUsername,
    String managerPassword,
  ) async {
    final order = orders.where((o) => o.id == orderId).firstOrNull;
    if (order == null) {
      return {'ok': false, 'error': 'Order not found'};
    }
    if (order.voided) {
      return {'ok': false, 'error': 'Order is already voided'};
    }

    final manager = staffUsers.firstWhere(
      (u) =>
          u.username.toLowerCase() == managerUsername.trim().toLowerCase() &&
          u.isManager,
      orElse: () => const StaffUser(
          id: '', username: '', password: '', name: '', role: ''),
    );

    // Verify manager/admin credentials against centralized backend first
    final remoteVoid = await supabaseService.voidOrderAtomic(
      orderId,
      reason,
      managerUsername.trim(),
      managerUsername: managerUsername.trim(),
      managerPassword: managerPassword,
    );

    if (remoteVoid['ok'] == true) {
      order.voided = true;
      order.voidReason = reason;
      order.voidedBy = (remoteVoid['voidedBy'] as String?) ??
          (manager.id.isNotEmpty ? manager.id : null);
      order.isSynced = true;
      await localStorage.addOrder(order);
      await syncService.syncAll();
      notifyListeners();
      return {'ok': true};
    }

    // Fallback local verification if offline
    if (manager.id.isEmpty || manager.password != managerPassword) {
      return {
        'ok': false,
        'error':
            remoteVoid['error']?.toString() ?? 'Invalid manager credentials'
      };
    }

    order.voided = true;
    order.voidReason = reason;
    order.voidedBy = manager.id;
    order.isSynced = false;
    await localStorage.addOrder(order);
    notifyListeners();
    return {'ok': true};
  }

  Future<Map<String, dynamic>> voidCheckout(
    String reason,
    String managerUsername,
    String managerPassword,
  ) async {
    if (cart.isEmpty) {
      return {'ok': false, 'error': 'No items to void.'};
    }
    if (reason.trim().isEmpty) {
      return {'ok': false, 'error': 'Enter a reason for voiding.'};
    }

    StaffUser? manager;
    if (currentUser?.isManager == true &&
        managerUsername.trim().isEmpty &&
        managerPassword.isEmpty) {
      manager = currentUser;
    } else {
      manager = await authenticateStaffForPurpose(
        managerUsername.trim(),
        managerPassword,
        accepts: (staff) => staff.isManager,
      );
      if (manager == null) {
        return {'ok': false, 'error': 'Manager or Admin credentials required.'};
      }
    }

    final now = ManilaTime.now();
    final createdAt = ManilaTime.utcIsoFromManilaWallTime(now);
    final order = Order(
      id: 'ord-${now.millisecondsSinceEpoch}',
      createdAt: createdAt,
      baristaName: currentUser?.name ?? 'Owner',
      baristaUserId: currentUser?.id,
      items: List<OrderItem>.from(cart),
      subtotal: subtotal,
      discount: discountAmount,
      promoLabel: promoLabel,
      total: total,
      paymentMethod: paymentMethod,
      ticketNo: '',
      paid: 0,
      change: 0,
      voided: true,
      voidReason: reason.trim(),
      voidedBy: manager!.id,
      isSynced: false,
    );

    final result = syncService.isOnline
        ? await supabaseService.pushOrderAtomic(
            order,
            const [],
            managerUsername: manager.username,
            managerPassword: managerPassword,
          )
        : {'ok': false, 'retryable': true};
    if (result['ok'] != true && result['retryable'] != true) {
      return {
        'ok': false,
        'error': result['error'] ?? 'Unable to void checkout.'
      };
    }

    if (result['ok'] != true) {
      await localStorage.addOrder(order);
      orders.insert(0, order);
      clearCart();
      paymentMethod = 'cash';
      syncService.updatePendingCount();
      notifyListeners();
      return {'ok': true, 'queued': true};
    }

    order.isSynced = true;
    if (result['ticketNo'] != null &&
        result['ticketNo'].toString().isNotEmpty) {
      order.ticketNo = result['ticketNo'].toString();
    }
    await localStorage.addOrder(order);
    orders.insert(0, order);
    clearCart();
    paymentMethod = 'cash';
    await syncService.syncAll();
    notifyListeners();
    return {'ok': true};
  }

  Future<StaffUser?> authenticateStaffForPurpose(
    String username,
    String password, {
    required bool Function(StaffUser staff) accepts,
  }) async {
    final auth = await supabaseService.authenticateStaff(
      username,
      password,
      persistSessionToken: false,
    );

    if (auth['ok'] == true && auth['user'] is StaffUser) {
      final staff = auth['user'] as StaffUser;
      if (!accepts(staff)) return null;

      await localStorage.saveOfflineStaffCredential(staff.id, password);
      final cachedStaff = localStorage.getStaff()
        ..removeWhere((cached) => cached.id == staff.id);
      cachedStaff.insert(0, staff);
      await localStorage.saveStaff(cachedStaff);
      return staff;
    }

    if (auth['offline'] != true) return null;

    final normalizedUsername = username.trim().toLowerCase();
    final staff = localStorage.getStaff().where((cached) {
      return cached.username.trim().toLowerCase() == normalizedUsername ||
          cached.name.trim().toLowerCase() == normalizedUsername;
    }).firstOrNull;
    if (staff == null || !accepts(staff)) return null;

    final savedPassword =
        await localStorage.getOfflineStaffCredential(staff.id);
    return savedPassword == password ? staff : null;
  }

  Future<StaffUser?> authenticateCachedStaffOffline({
    required String email,
    required String password,
  }) async {
    final identifier = email.trim().toLowerCase();
    final staff = localStorage.getStaff().where((cached) {
      return cached.role == 'cashier' &&
          (cached.email.trim().toLowerCase() == identifier ||
              cached.username.trim().toLowerCase() == identifier);
    }).firstOrNull;
    if (staff == null) return null;

    final savedPassword =
        await localStorage.getOfflineStaffCredential(staff.id);
    return savedPassword == password ? staff : null;
  }

  Future<Map<String, dynamic>> requestVoidApproval(
    String? orderId,
    String reason,
  ) async {
    final requester = currentUser;
    if (requester == null || requester.id.isEmpty) {
      return {
        'ok': false,
        'error': 'Unable to identify the requesting staff member.'
      };
    }
    if (reason.trim().isEmpty) {
      return {'ok': false, 'error': 'Enter a reason for voiding.'};
    }
    if (voidRequests.any((request) =>
        request.requestedById == requester.id && request.status == 'pending')) {
      return {
        'ok': false,
        'error': 'You already have a void request waiting for Admin approval.'
      };
    }

    final targetOrder = orderId == null
        ? null
        : orders.where((order) => order.id == orderId).firstOrNull;
    if (orderId != null && targetOrder == null) {
      return {'ok': false, 'error': 'Ticket not found.'};
    }
    if (targetOrder?.voided == true) {
      return {'ok': false, 'error': 'Ticket is already voided.'};
    }

    final requestItems = targetOrder == null
        ? List<OrderItem>.from(cart)
        : List<OrderItem>.from(targetOrder.items);
    if (requestItems.isEmpty) {
      return {'ok': false, 'error': 'No items to void.'};
    }

    final requestedAt = ManilaTime.utcNowIso8601();
    final request = VoidRequest(
      id: 'void-request-${DateTime.now().millisecondsSinceEpoch}',
      requestedAt: requestedAt,
      requestedById: requester.id,
      requestedByName: requester.name,
      reason: reason.trim(),
      orderId: targetOrder?.id,
      items: requestItems,
      subtotal: targetOrder?.subtotal ?? subtotal,
      discount: targetOrder?.discount ?? discountAmount,
      promoLabel: targetOrder?.promoLabel ?? promoLabel,
      total: targetOrder?.total ?? total,
      paymentMethod: targetOrder?.paymentMethod ?? paymentMethod,
      isSynced: false,
    );

    await localStorage.addVoidRequest(request);
    voidRequests.insert(0, request);
    if (targetOrder == null) pendingCartVoidRequestId = request.id;
    if (targetOrder == null) _persistActiveCheckout();

    final synced = await supabaseService.pushVoidRequest(request);
    if (synced) {
      request.isSynced = true;
      await localStorage.saveVoidRequests(voidRequests);
      await localStorage.removePendingVoidRequest(request.id);
    }
    syncService.updatePendingCount();
    notifyListeners();
    if (synced) await syncService.syncAll();

    return {'ok': true, 'synced': synced, 'requestId': request.id};
  }

  // --- Inventory & Restock Operations (Synced with Admin) ---
  Future<void> addOrUpdateInventoryItem(InventoryItem item) async {
    final idx = inventory.indexWhere((i) => i.id == item.id);
    if (idx >= 0) {
      inventory[idx] = item;
    } else {
      inventory.add(item);
    }
    await localStorage.saveInventory(inventory);
    notifyListeners();

    await supabaseService.upsertInventoryItem(item);
    await syncService.syncAll();
  }

  Future<Map<String, dynamic>> deleteInventoryItem(String id) async {
    final res = await supabaseService.deleteInventoryItem(id);
    if (res['ok'] == true) {
      inventory.removeWhere((i) => i.id == id);
      await localStorage.saveInventory(inventory);
      await syncService.syncAll();
      notifyListeners();
      return {'ok': true};
    }
    return res;
  }

  Future<void> addRestockRecord({
    required String? inventoryItemId,
    required String itemName,
    required double quantityAdded,
    double? purchaseQty,
    String? purchaseUnit,
  }) async {
    final now = ManilaTime.utcNowIso8601();
    final record = RestockRecord(
      id: 'rst-${DateTime.now().millisecondsSinceEpoch}',
      inventoryItemId: inventoryItemId,
      itemName: itemName,
      quantityAdded: quantityAdded,
      purchaseQty: purchaseQty,
      purchaseUnit: purchaseUnit ?? 'pcs',
      date: now,
      isSynced: false,
    );

    final synced = await supabaseService.pushRestockAtomic(record);
    record.isSynced = synced;

    await localStorage.addRestock(record);
    restocks.insert(0, record);

    if (inventoryItemId != null) {
      final item = inventory.where((i) => i.id == inventoryItemId).firstOrNull;
      if (item != null) {
        item.stock += quantityAdded;
        await localStorage.saveInventory(inventory);
      }
    }

    syncService.updatePendingCount();
    notifyListeners();
    await syncService.syncAll();
  }

  Future<void> restockItem(String inventoryItemId, double piecesQty,
      [String? notes]) async {
    final item = inventory.where((i) => i.id == inventoryItemId).firstOrNull;
    if (item == null) return;
    final unitSize =
        (item.purchaseUnitSize != null && item.purchaseUnitSize! > 0)
            ? item.purchaseUnitSize!
            : 1.0;
    final baseQtyAdded = piecesQty * unitSize;

    await addRestockRecord(
      inventoryItemId: inventoryItemId,
      itemName: item.name,
      quantityAdded: baseQtyAdded,
      purchaseQty: piecesQty,
      purchaseUnit: 'pcs',
    );
  }

  Future<RestockDeleteResult> deleteRestock(String restockId) async {
    final existing = restocks.where((r) => r.id == restockId).firstOrNull;
    var deleted = await supabaseService.deleteRestockAtomic(restockId);
    if (!deleted) {
      try {
        await localStorage.addPendingRestockDelete(restockId);
      } catch (_) {
        return RestockDeleteResult.failed;
      }
    } else {
      await localStorage.removePendingRestockDelete(restockId);
    }

    restocks.removeWhere((r) => r.id == restockId);
    await localStorage.saveRestocks(restocks);
    await localStorage.removePendingRestock(restockId);

    if (existing != null) {
      final item = inventory
          .where((i) =>
              (existing.inventoryItemId != null &&
                  i.id == existing.inventoryItemId) ||
              i.name.trim().toLowerCase() ==
                  existing.itemName.trim().toLowerCase())
          .firstOrNull;
      if (item != null) {
        item.stock =
            (item.stock - existing.quantityAdded).clamp(0.0, double.infinity);
        await localStorage.saveInventory(inventory);
      }
    }
    notifyListeners();

    await syncService.syncAll();
    deleted = !localStorage.getPendingRestockDeletes().contains(restockId);
    return deleted ? RestockDeleteResult.deleted : RestockDeleteResult.queued;
  }

  // --- Shift Clock In / Out ---
  Future<void> punchShift(StaffUser staff, String type) async {
    if (!staff.canAccessBaristaShift || (type != 'login' && type != 'logout')) {
      return;
    }
    final alreadyOnShift =
        onShiftBaristas.any((barista) => barista.id == staff.id);
    if ((type == 'login' && alreadyOnShift) ||
        (type == 'logout' && !alreadyOnShift)) {
      return;
    }

    await _recordLoginActivity(staff, type, idPrefix: 'shift');
  }

  Future<void> _recordLoginActivity(
    StaffUser staff,
    String type, {
    required String idPrefix,
  }) async {
    final now = ManilaTime.utcNowIso8601();
    final log = LoginActivity(
      id: '$idPrefix-${staff.id}-${DateTime.now().microsecondsSinceEpoch}-$type',
      userId: staff.id,
      username: staff.username,
      name: staff.name,
      role: staff.role,
      type: type,
      at: now,
      isSynced: false,
    );

    await localStorage.addLoginActivity(log);
    shiftLogs.insert(0, log);
    if (staff.canAccessBaristaShift) _restoreOnShiftBarista();
    syncService.updatePendingCount();
    notifyListeners();

    final ok = await supabaseService.pushLoginActivity(log);
    if (ok) {
      log.isSynced = true;
      await localStorage.removePendingLoginActivity(log.id);
      await localStorage.saveLoginActivity(shiftLogs);
    }

    syncService.updatePendingCount();
    notifyListeners();
    await syncService.syncAll();
  }
}
