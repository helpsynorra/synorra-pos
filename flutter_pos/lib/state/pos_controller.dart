import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
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

int? _ticketNumberForOrder(Order order) {
  final value = order.ticketNo.trim();
  if (value.isEmpty) return null;
  final digits = value.replaceFirst('#', '').replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  final parsed = int.tryParse(digits);
  return parsed != null && parsed > 0 ? parsed : null;
}

String nextTicketNoForOrders(List<Order> orders, DateTime now) {
  final sameDay = orders.where((order) {
    final createdAt = ManilaTime.parse(order.createdAt);
    if (createdAt == null) return false;
    if (createdAt.year != now.year ||
        createdAt.month != now.month ||
        createdAt.day != now.day) {
      return false;
    }
    if (order.isWaste ||
        order.paymentMethod == 'waste' ||
        order.id.toLowerCase().startsWith('waste-')) {
      return false;
    }
    return true;
  }).toList();

  final activeTicketNumbers = <int>{};
  for (final order in sameDay) {
    final ticketNo = _ticketNumberForOrder(order);
    if (ticketNo == null) continue;
    if (!order.voided) activeTicketNumbers.add(ticketNo);
  }

  var nextTicket = 1;
  while (activeTicketNumbers.contains(nextTicket)) {
    nextTicket++;
  }
  return '#${nextTicket.toString().padLeft(3, '0')}';
}

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
  String paymentMethod =
      'cash'; // cash, gcash, maya, cards, grab, foodpanda, or split details
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
        (category) => category != 'All' && availableCategories.remove(category),
      ),
      ...syncedCategories.where(
        (category) => category != 'All' && availableCategories.remove(category),
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
    final active = LoginActivity.openStaffShifts(shiftLogs);
    onShiftBaristas = active
        .map((event) =>
            staffUsers.where((staff) => staff.id == event.userId).firstOrNull)
        .whereType<StaffUser>()
        .toList();
    final onShift =
        active.where((event) => event.role == 'barista').firstOrNull;
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

    if (staff.canClockShift) {
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
      promoItemQty = (saved['promoItemQty'] as num?)?.toInt() ??
          (promoItemIndex == null ? null : 1);
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
    final ledgers = getStockLedgers(
      inventory,
      range: range,
      selectedDate: selectedDate,
    );
    double total = 0.0;
    for (final item in inventory) {
      if (isCupInventoryItem(item)) {
        total += ledgers[item.id]?['usedPerUnit'] ?? 0.0;
      }
    }
    return total;
  }

  // Calculate the shared transaction indexes once for the whole Stock screen.
  Map<String, Map<String, double>> getStockLedgers(
    Iterable<InventoryItem> items, {
    String range = 'Today',
    DateTime? selectedDate,
  }) {
    final restockedById = <String, double>{};
    final restockedByName = <String, double>{};
    final restockedByIdAndName = <String, double>{};
    final usedById = <String, double>{};
    final usedByName = <String, double>{};
    final usedByIdAndName = <String, double>{};
    final loggedOrderIds = <String>{};

    void addAmount(
      Map<String, double> byId,
      Map<String, double> byName,
      Map<String, double> byIdAndName,
      String id,
      String name,
      double amount,
    ) {
      if (id.isNotEmpty) {
        byId.update(id, (value) => value + amount, ifAbsent: () => amount);
      }
      if (name.isNotEmpty) {
        byName.update(name, (value) => value + amount, ifAbsent: () => amount);
      }
      if (id.isNotEmpty && name.isNotEmpty) {
        final key = '$id\u0000$name';
        byIdAndName.update(
          key,
          (value) => value + amount,
          ifAbsent: () => amount,
        );
      }
    }

    double amountFor(
      Map<String, double> byId,
      Map<String, double> byName,
      Map<String, double> byIdAndName,
      InventoryItem item,
    ) {
      final name = item.name.trim().toLowerCase();
      final pairKey = '${item.id}\u0000$name';
      return (byId[item.id] ?? 0) +
          (byName[name] ?? 0) -
          (byIdAndName[pairKey] ?? 0);
    }

    for (final record in restocks) {
      if (!_isInRange(record.date, range, selectedDate)) continue;
      addAmount(
        restockedById,
        restockedByName,
        restockedByIdAndName,
        record.inventoryItemId ?? '',
        record.itemName.trim().toLowerCase(),
        record.quantityAdded,
      );
    }

    final usageLogs = recipesData['usageLogs'] is List
        ? (recipesData['usageLogs'] as List)
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
        : const <Map<String, dynamic>>[];
    for (final usage in usageLogs) {
      final orderId = usage['orderId']?.toString() ?? '';
      if (orderId.isNotEmpty) loggedOrderIds.add(orderId);
      if (!_isInRange(usage['date']?.toString() ?? '', range, selectedDate)) {
        continue;
      }
      addAmount(
        usedById,
        usedByName,
        usedByIdAndName,
        usage['inventoryItemId']?.toString() ?? '',
        (usage['itemName']?.toString() ?? '').trim().toLowerCase(),
        (usage['usedAmount'] as num?)?.toDouble() ?? 0.0,
      );
    }

    final fallbackOrders = orders.where((order) {
      return !order.voided &&
          !loggedOrderIds.contains(order.id) &&
          _isInRange(order.createdAt, range, selectedDate);
    }).toList();
    if (fallbackOrders.isNotEmpty) {
      for (final deduction
          in syncService.buildDeductionsForOrders(fallbackOrders)) {
        addAmount(
          usedById,
          usedByName,
          usedByIdAndName,
          deduction['inventoryItemId']?.toString() ?? '',
          (deduction['itemName']?.toString() ?? '').trim().toLowerCase(),
          (deduction['amount'] as num?)?.toDouble() ?? 0.0,
        );
      }
    }

    final result = <String, Map<String, double>>{};
    for (final item in items) {
      final totalRestocked = amountFor(
        restockedById,
        restockedByName,
        restockedByIdAndName,
        item,
      );
      final totalUsed = amountFor(
        usedById,
        usedByName,
        usedByIdAndName,
        item,
      );
      final pieceSize =
          (item.purchaseUnitSize != null && item.purchaseUnitSize! > 0)
              ? item.purchaseUnitSize!
              : 1.0;
      final remainingBase = item.stock;
      final openingBase = (remainingBase - totalRestocked + totalUsed)
          .clamp(0.0, double.infinity);
      final openingPcs = openingBase / pieceSize;
      final restockedPcs = totalRestocked / pieceSize;
      final usedPcs =
          (item.purchaseUnitSize != null && item.purchaseUnitSize! > 0)
              ? totalUsed / item.purchaseUnitSize!
              : -1.0;
      final remainingPcs =
          (remainingBase / pieceSize).clamp(0.0, double.infinity);

      double? cupsLeft;
      if (item.unit.trim().toLowerCase() != 'pcs') {
        if (item.cupUsageAmount != null && item.cupUsageAmount! > 0) {
          cupsLeft = remainingBase / item.cupUsageAmount!;
        } else if (item.cupsMake != null && item.cupsMake! > 0) {
          cupsLeft = item.cupsMake!;
        }
      }
      result[item.id] = {
        'openingPcs': openingPcs,
        'restockedPcs': restockedPcs,
        'usedPerUnit': totalUsed,
        'usedPcs': usedPcs,
        'remainingPcs': remainingPcs,
        'cupsLeft': cupsLeft ?? -1.0,
      };
    }
    return result;
  }

  Map<String, double> getStockLedger(
    InventoryItem item, {
    String range = 'Today',
    DateTime? selectedDate,
  }) {
    return getStockLedgers(
      [item],
      range: range,
      selectedDate: selectedDate,
    )[item.id]!;
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

  Future<void> persistMenuState({
    List<MenuItem>? items,
    List<String>? categoryList,
    String? selected,
  }) async {
    final nextItems = items ?? List<MenuItem>.from(menu);
    final nextCategories = (categoryList ?? categories)
        .where((category) => category.trim().isNotEmpty)
        .toList();

    final normalizedCategories = <String>['All'];
    for (final category in nextCategories) {
      final trimmed = category.trim();
      if (trimmed.isEmpty || trimmed.toLowerCase() == 'all') continue;
      if (!normalizedCategories.any(
          (entry) => entry.trim().toLowerCase() == trimmed.toLowerCase())) {
        normalizedCategories.add(trimmed);
      }
    }

    menu = List<MenuItem>.from(nextItems);
    categories = List<String>.from(normalizedCategories);
    if (selected != null && selected.trim().isNotEmpty) {
      selectedCategory = selected.trim();
    } else if (!categories.contains(selectedCategory)) {
      selectedCategory = 'All';
    }

    await localStorage.saveMenu(menu);
    await localStorage.saveCategories(categories);
    await localStorage.saveCategoryOrder(
      categories.where((category) => category != 'All').toList(),
    );
    _refreshFromLocalStorage();
  }

  void refreshLocalMenuState() {
    _refreshFromLocalStorage();
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
    if (!RegExp(r'^(?:[A-Z0-9]{6}|[A-Z0-9]{1,16}-[A-Z0-9]{6})$')
        .hasMatch(code)) {
      return 'Invalid promo voucher.';
    }
    final promo = syncService.promotionCodes
        .where(
          (entry) => entry['code']?.toString().trim().toUpperCase() == code,
        )
        .firstOrNull;
    if (promo == null || code.isEmpty) return 'Invalid promo voucher.';
    if (_isPromotionRedeemed(promo)) return 'Promo voucher already used.';
    if (_isPromotionExpired(promo)) return 'This promo voucher has expired.';
    final value = (promo['discountValue'] as num?)?.toDouble() ?? 0;
    final isFreeItem = promo['discountType'] == 'item';
    final freeItemQty = value.round().clamp(1, 99).toInt();
    if (isFreeItem &&
        (itemIndex == null ||
            itemIndex < 0 ||
            itemIndex >= cart.length ||
            itemQty != freeItemQty ||
            itemQty! > cart[itemIndex].qty)) {
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
    final promo = syncService.promotionCodes
        .where(
          (entry) => entry['code']?.toString().trim().toUpperCase() == code,
        )
        .firstOrNull;
    if (promo == null ||
        _isPromotionRedeemed(promo) ||
        _isPromotionExpired(promo) ||
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
      if (promoItemIndex == null ||
          promoItemIndex! < 0 ||
          promoItemIndex! >= cart.length ||
          promoItemQty == null ||
          promoItemQty! > cart[promoItemIndex!].qty) {
        clearPromotion();
        return;
      }
      discountAmount =
          (cart[promoItemIndex!].unitPrice * promoItemQty!).roundToDouble();
      return;
    }
    final value = (promo['discountValue'] as num?)?.toDouble() ?? 0;
    final amount =
        promo['discountType'] == 'amount' ? value : subtotal * value / 100;
    discountAmount = amount.clamp(0, subtotal).roundToDouble();
  }

  bool _isPromotionRedeemed(Map<String, dynamic> promo) =>
      promo['redeemedAt'] != null || promo['redeemed_at'] != null;

  bool _isPromotionExpired(Map<String, dynamic> promo) {
    final rawExpiry = promo['expiresAt'] ?? promo['expires_at'];
    final expiresAt = DateTime.tryParse(rawExpiry?.toString() ?? '');
    return expiresAt != null && !DateTime.now().isBefore(expiresAt);
  }

  void clearPromotion() {
    final previousTotal = total;
    promoId = null;
    promoLabel = null;
    promoItemIndex = null;
    promoItemQty = null;
    discountAmount = 0;
    if (paymentMethod != 'cash' ||
        tenderedAmount == 0 ||
        tenderedAmount == previousTotal) {
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
        categoryType: product.categoryType ??
            localStorage.getCategoryTypes()[product.category],
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
      final orderId = 'ord-${const Uuid().v4()}';

      final localTicketNo = nextTicketNoForOrders(orders, now);

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

      isProcessing = false;
      notifyListeners();
      return {
        'ok': true,
        'order': order,
        'synced': false,
        'queued': true,
      };
    } catch (e) {
      isProcessing = false;
      notifyListeners();
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> recordWasteOrder(
      {required String reason}) async {
    if (!syncService.hasPermission('wasteManagement')) {
      return {
        'ok': false,
        'error': 'Waste recording is disabled for this POS.'
      };
    }
    if (isVoidRequestPending) {
      return {'ok': false, 'error': 'Resolve the pending void request first.'};
    }
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      return {
        'ok': false,
        'error': 'Please provide a reason or note for the waste.'
      };
    }
    if (cart.isEmpty) {
      return {'ok': false, 'error': 'Add wasted items first.'};
    }
    if (isProcessing) {
      return {'ok': false, 'error': 'Please wait for the current order.'};
    }

    isProcessing = true;
    notifyListeners();
    try {
      final now = ManilaTime.now();
      final createdAt = ManilaTime.utcIsoFromManilaWallTime(now);
      final cashierShift = LoginActivity.openStaffShifts(shiftLogs)
          .where((shift) => shift.role.trim().toLowerCase() == 'pos_cashier')
          .firstOrNull;
      final cashier = cashierShift == null
          ? null
          : staffUsers
              .where((staff) => staff.id == cashierShift.userId)
              .firstOrNull;
      final order = Order(
        id: 'waste-${const Uuid().v4()}',
        createdAt: createdAt,
        baristaName: cashier?.name ?? cashierShift?.name ?? '—',
        baristaUserId: cashier?.id ?? cashierShift?.userId,
        items: List.from(cart),
        subtotal: 0,
        discount: 0,
        total: 0,
        paymentMethod: 'waste',
        serviceMode: serviceMode,
        ticketNo: '',
        paid: 0,
        change: 0,
        voided: false,
        wasteReason: trimmedReason,
        isSynced: false,
      );
      final deductions = syncService.buildDeductionsForOrder(order);
      await localStorage.addOrder(order);
      orders.insert(0, order);
      for (final deduction in deductions) {
        final stockItem = inventory
            .where((item) => item.id == deduction['inventoryItemId'])
            .firstOrNull;
        final amount = (deduction['amount'] as num?)?.toDouble() ?? 0;
        if (stockItem != null && amount > 0) {
          stockItem.stock =
              (stockItem.stock - amount).clamp(0.0, double.infinity);
        }
      }
      await localStorage.saveInventory(inventory);
      clearCart();
      syncService.updatePendingCount();
      return {
        'ok': true,
        'order': order,
        'synced': false,
        'queued': true,
      };
    } catch (error) {
      return {'ok': false, 'error': error.toString()};
    } finally {
      isProcessing = false;
      notifyListeners();
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

    final manager = await authenticateStaffForPurpose(
      managerUsername.trim(),
      managerPassword,
      accepts: (staff) => staff.isManager,
    );
    if (manager == null) {
      return {'ok': false, 'error': 'Invalid manager credentials'};
    }

    order.voided = true;
    order.voidReason = reason;
    order.voidedBy = manager.id;
    order.isSynced = false;
    await localStorage.addOrder(order);
    syncService.updatePendingCount();
    notifyListeners();
    return {'ok': true, 'queued': true};
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
      id: 'ord-${const Uuid().v4()}',
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

    await localStorage.addOrder(order);
    orders.insert(0, order);
    clearCart();
    paymentMethod = 'cash';
    syncService.updatePendingCount();
    notifyListeners();
    return {'ok': true, 'queued': true};
  }

  Future<StaffUser?> authenticateStaffForPurpose(
    String username,
    String password, {
    required bool Function(StaffUser staff) accepts,
  }) async {
    final normalizedUsername = username.trim().toLowerCase();
    final cachedStaff = localStorage.getStaff().where((cached) {
      return cached.username.trim().toLowerCase() == normalizedUsername ||
          cached.name.trim().toLowerCase() == normalizedUsername;
    }).firstOrNull;
    if (cachedStaff != null) {
      if (!accepts(cachedStaff)) return null;
      final savedPassword =
          await localStorage.getOfflineStaffCredential(cachedStaff.id);
      return savedPassword == password ? cachedStaff : null;
    }

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

    return null;
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

    try {
      await localStorage.migrateLegacyStaffCredentials();
    } catch (_) {
      // Still try the secure credential store if legacy migration fails.
    }
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

    syncService.updatePendingCount();
    notifyListeners();

    return {
      'ok': true,
      'synced': false,
      'queued': true,
      'requestId': request.id
    };
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
    await localStorage.queueInventoryItem(item);
    notifyListeners();
    syncService.updatePendingCount();
  }

  Future<Map<String, dynamic>> deleteInventoryItem(String id) async {
    inventory.removeWhere((i) => i.id == id);
    await localStorage.saveInventory(inventory);
    await localStorage.queueInventoryDelete(id);
    syncService.updatePendingCount();
    notifyListeners();
    return {'ok': true, 'queued': true};
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
    await localStorage.addPendingRestockDelete(restockId);

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

    syncService.updatePendingCount();
    return RestockDeleteResult.queued;
  }

  // --- Shift Clock In / Out ---
  Future<void> punchShift(
    StaffUser staff,
    String type,
  ) async {
    if (!staff.canClockShift || (type != 'login' && type != 'logout')) {
      return;
    }
    final alreadyOnShift =
        onShiftBaristas.any((barista) => barista.id == staff.id);
    if ((type == 'login' && alreadyOnShift) ||
        (type == 'logout' && !alreadyOnShift)) {
      return;
    }

    await _recordLoginActivity(
      staff,
      type,
      idPrefix: 'shift',
    );
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
    syncService.updatePendingCount();
    notifyListeners();
  }
}
