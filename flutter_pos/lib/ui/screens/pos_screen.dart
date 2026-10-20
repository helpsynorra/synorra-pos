// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/menu_item.dart';
import '../../models/order.dart';
import '../../services/sync_service.dart';
import '../../state/pos_controller.dart';
import '../widgets/product_card.dart';
import '../widgets/cart_panel.dart';
import '../widgets/drink_options_dialog.dart';
import '../widgets/receipt_dialog.dart';
import '../widgets/void_dialog.dart';
import '../widgets/barista_shift_dialog.dart';
import '../widgets/bluetooth_printer_picker_dialog.dart';
import '../widgets/pos_navigation_drawer.dart';
import '../widgets/pos_app_bar.dart';
import '../../services/bluetooth_printer_service.dart';
import 'stock_screen.dart';
import 'restock_screen.dart';
import 'login_screen.dart';
import 'support_account_screens.dart';

class PosScreen extends StatefulWidget {
  final PosController controller;

  const PosScreen({super.key, required this.controller});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final BluetoothPrinterService _printerService =
      BluetoothPrinterService.instance;
  String? _selectedItemId;
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChange);
    widget.controller.syncService.addListener(_onControllerChange);
    _printerService.addListener(_onControllerChange);
    _printerService.initialize();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    widget.controller.syncService.removeListener(_onControllerChange);
    _printerService.removeListener(_onControllerChange);
    super.dispose();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  Future<void> _openBackOffice() async {
    final uri = Uri.parse('https://synorra-pos.vercel.app/back-office');
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Back office.')),
        );
      }
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Back office.')),
        );
      }
    }
  }

  void _openHelpCenter() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SupportHubScreen(
        canDeleteOwnerAccount: widget.controller.currentUser?.role == 'cashier',
        onOpenDeleteAccount: _openDeleteAccount,
      ),
    ));
  }

  void _openDeleteAccount() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DeleteOwnerAccountScreen(
        onDelete: (password) async {
          await widget.controller.supabaseService.deleteOwnerAccount(password);
          await widget.controller.clearActiveSession();
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(
              builder: (_) => LoginScreen(controller: widget.controller),
            ),
            (_) => false,
          );
        },
      ),
    ));
  }

  Future<void> _openPrinterPicker(PrinterRole role) async {
    final permission =
        role == PrinterRole.labels ? 'connectLabels' : 'connectReceipt';
    if (!widget.controller.syncService.hasPermission(permission)) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => BluetoothPrinterPickerDialog(role: role),
    );
  }

  Future<void> _printOrder(Order order) async {
    final results = <String>[];
    if (widget.controller.syncService.hasPermission('customerReceipt')) {
      try {
        await _printerService.printReceipt(order);
        results.add('Receipt sent');
      } catch (error) {
        results.add('Receipt: $error');
      }
    }
    if (widget.controller.syncService.hasPermission('cupLabels')) {
      try {
        await _printerService.printLabels(
          order,
          menu: widget.controller.menu,
        );
        results.add('Labels sent');
      } catch (error) {
        results.add('Labels: $error');
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(results.join(' | '))),
      );
    }
  }

  void _openDrinkOptions(MenuItem item) {
    setState(() => _selectedItemId = item.id);
    if (item.addons.isEmpty &&
        item.styles.length == 1 &&
        item.styles.single.toLowerCase() == 'iced') {
      widget.controller.addToCart(item, style: 'iced');
      return;
    }

    if (item.styles.isNotEmpty || item.addons.isNotEmpty) {
      showDialog(
        context: context,
        builder: (_) => DrinkOptionsDialog(
          item: item,
          onConfirm: (style, addons, qty) {
            widget.controller
                .addToCart(item, style: style, addons: addons, qty: qty);
          },
        ),
      );
    } else {
      widget.controller.addToCart(item);
    }
  }

  void _openVoidDialog() {
    if (widget.controller.cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items in checkout to void.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => VoidDialog(
        cart: widget.controller.cart,
        isManager: (widget.controller.currentUser?.isManager ?? false) &&
            (widget.controller.currentUser?.password.isNotEmpty ?? false),
        isRequestPending: widget.controller.isVoidRequestPending,
        isOnline: widget.controller.syncService.isOnline,
        onConfirmVoid: (reason, managerUser, managerPass) async {
          final username = managerUser.isNotEmpty
              ? managerUser
              : widget.controller.currentUser?.username ?? '';
          final password = managerPass.isNotEmpty
              ? managerPass
              : widget.controller.currentUser?.password ?? '';
          final res =
              await widget.controller.voidCheckout(reason, username, password);
          if (res['ok'] == true && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(res['queued'] == true
                    ? 'Void saved offline and will sync when online.'
                    : 'Checkout voided.'),
              ),
            );
          }
          return res;
        },
        onRequestVoid: (reason) async {
          final result =
              await widget.controller.requestVoidApproval(null, reason);
          if (result['ok'] == true && mounted) {
            final synced = result['synced'] == true;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(synced
                    ? 'Void request sent to Admin. Waiting for approval.'
                    : 'Void request saved and will sync when online.'),
              ),
            );
          }
          return result;
        },
      ),
    );
  }

  void _openReceiptDialog([Order? targetOrder]) {
    if (!widget.controller.syncService.hasPermission('printButton')) return;
    final order = targetOrder ??
        widget.controller.lastCompletedOrder ??
        (widget.controller.orders.isNotEmpty
            ? widget.controller.orders.first
            : null);
    if (order == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No orders found to print')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => ReceiptDialog(
        order: order,
        orders: widget.controller.orders,
        menu: widget.controller.menu,
        onPrint: _printOrder,
        customerReceiptEnabled:
            widget.controller.syncService.hasPermission('customerReceipt'),
        cupLabelsEnabled:
            widget.controller.syncService.hasPermission('cupLabels'),
        printButtonEnabled:
            widget.controller.syncService.hasPermission('printButton'),
      ),
    );
  }

  void _openBaristaShiftDialog() {
    showDialog(
      context: context,
      builder: (_) => BaristaShiftDialog(
        onShiftBaristas: widget.controller.onShiftBaristas,
        authenticateBarista: (username, password) async {
          return widget.controller.authenticateStaffForPurpose(
            username,
            password,
            accepts: (staff) => staff.canAccessBaristaShift,
          );
        },
        onPunch: (staff, type) async {
          await widget.controller.punchShift(staff, type);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    '${staff.name} clocked ${type == "login" ? "in" : "out"}')),
          );
        },
      ),
    );
  }

  Future<void> _handleProceedOrder({VoidCallback? closeMobileCheckout}) async {
    final controller = widget.controller;
    final permissions = controller.syncService;
    final dineInEnabled = permissions.hasPermission('dineIn');
    final takeOutEnabled = permissions.hasPermission('takeOut');
    // Service-mode permissions control which choices are available. They must
    // not block checkout when both choices are disabled; in that case keep the
    // current mode and let the order proceed.
    if (dineInEnabled || takeOutEnabled) {
      if (controller.serviceMode == 'dine-in' && !dineInEnabled) {
        controller.setServiceMode('take-out');
      } else if (controller.serviceMode == 'take-out' && !takeOutEnabled) {
        controller.setServiceMode('dine-in');
      }
    }
    final stockShortfalls =
        controller.syncService.findStockShortfalls(controller.cart);
    if (stockShortfalls.isNotEmpty) {
      final number = NumberFormat('0.##');
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Low stock warning'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                const Text('The following items do not have enough stock:'),
                const SizedBox(height: 8),
                for (final item in stockShortfalls)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${item['itemName']}: ${number.format(item['required'])} '
                      '${item['unit']} required, '
                      '${number.format(item['available'])} available',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final wasOffline = !controller.syncService.isOnline;
    final res = await controller.proceedOrder();
    final offline = wasOffline ||
        !controller.syncService.isOnline ||
        res['networkFailure'] == true;
    if (res['ok'] == true && mounted) {
      final order = res['order'] as Order;
      if (res['synced'] != true && !offline) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved on this device only. Server sync failed: ${res['syncError']}',
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
      closeMobileCheckout?.call();
      _openReceiptDialog(order);
    } else if (mounted && !offline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout failed: ${res['error']}')),
      );
    }
  }

  void _openMobileCartSheet() {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            Expanded(
              child: CartPanel(
                controller: widget.controller,
                dineInEnabled:
                    widget.controller.syncService.hasPermission('dineIn'),
                takeOutEnabled:
                    widget.controller.syncService.hasPermission('takeOut'),
                isFullWidth: true,
                isKeyboardOpen: keyboardOpen,
                onProceedOrder: () => _handleProceedOrder(
                  closeMobileCheckout: () {
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToPos() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _navigateToStock() {
    if (!widget.controller.syncService.hasPermission('stockInventory')) return;
    _navigateToPos();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StockScreen(
          controller: widget.controller,
          drawerBuilder: _buildPosDrawer,
          onPrint: _openReceiptDialog,
          onVoid: _openVoidDialog,
        ),
      ),
    );
  }

  void _navigateToRestock() {
    if (!widget.controller.syncService.hasPermission('restockInventory'))
      // ignore: curly_braces_in_flow_control_structures
      return;
    _navigateToPos();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RestockScreen(
          controller: widget.controller,
          drawerBuilder: _buildPosDrawer,
          onPrint: _openReceiptDialog,
          onVoid: _openVoidDialog,
        ),
      ),
    );
  }

  Widget _buildPosDrawer(PosSection section) {
    final controller = widget.controller;
    final canLogout = controller.cart.isEmpty &&
        !controller.isVoidRequestPending &&
        !_isLoggingOut;

    return PosNavigationDrawer(
      selectedSection: section,
      cashierName: controller.currentUser?.name ?? 'Owner',
      labelsConnection: _printerService.connectionSummary(PrinterRole.labels),
      receiptConnection: _printerService.connectionSummary(PrinterRole.receipt),
      syncStatus: controller.syncService.isOnline ? 'Online' : 'Offline',
      canLogout: canLogout,
      inventoryFeaturesEnabled: controller.syncService.inventoryFeaturesEnabled,
      stockInventoryEnabled:
          controller.syncService.hasPermission('stockInventory'),
      restockInventoryEnabled:
          controller.syncService.hasPermission('restockInventory'),
      connectLabelsEnabled:
          controller.syncService.hasPermission('connectLabels'),
      connectReceiptEnabled:
          controller.syncService.hasPermission('connectReceipt'),
      logoutDisabledMessage: controller.isVoidRequestPending
          ? 'Wait for void approval first'
          : 'Clear checkout first',
      onOpenTerminal: _navigateToPos,
      onOpenStock: _navigateToStock,
      onOpenRestock: _navigateToRestock,
      onOpenBaristas: _openBaristaShiftDialog,
      onOpenBackOffice: _openBackOffice,
      onOpenHelpCenter: _openHelpCenter,
      onConnectLabels: () => _openPrinterPicker(PrinterRole.labels),
      onConnectReceipt: () => _openPrinterPicker(PrinterRole.receipt),
      onSync: () => controller.syncService.syncAll(),
      onLogout: _handleLogout,
    );
  }

  Future<void> _handleLogout() async {
    setState(() => _isLoggingOut = true);
    final cashier = widget.controller.currentUser;
    try {
      if (cashier != null) {
        await widget.controller.recordStaffSessionEvent(cashier, 'logout');
      }
      await widget.controller.clearActiveSession();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(controller: widget.controller),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final sync = controller.syncService;
    final filteredItems = controller.filteredMenu;
    final currency = NumberFormat('#,##0', 'en_PH');
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    final syncStatusLabel = sync.isOnline ? 'Online' : 'Offline';
    final syncDotColor =
        sync.isOnline ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF);

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      appBar: PosAppBar(
        isVoidRequestPending: controller.isVoidRequestPending,
        showPrintButton:
            !sync.printButtonHidden && sync.hasPermission('printButton'),
        syncStatus: syncStatusLabel,
        syncDotColor: syncDotColor,
        onPrint: _openReceiptDialog,
        onSync: () => sync.syncAll(),
      ),
      drawer: _buildPosDrawer(PosSection.terminal),
      body: LayoutBuilder(
        builder: (context, screenConstraints) {
          final checkoutPanelWidth =
              screenConstraints.maxWidth >= 1280 ? 400.0 : 370.0;
          final isWide = screenConstraints.maxWidth >= 960;
          final cartItemCount =
              controller.cart.fold<int>(0, (sum, i) => sum + i.qty);

          final menuSection = Container(
            color: const Color(0xFFF9FAFB),
            child: Column(
              children: [
                // Responsive Product Grid
                Expanded(
                  child: filteredItems.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              sync.status == SyncStatus.syncing
                                  ? 'Syncing menu from Admin...'
                                  : 'No menu items found in this category.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Color(0xFF9CA3AF), fontSize: 14),
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            int crossAxisCount = 4;
                            if (constraints.maxWidth < 360) {
                              crossAxisCount = 1;
                            } else if (constraints.maxWidth < 520) {
                              crossAxisCount = 2;
                            }
                            return GridView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisExtent: 160,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: filteredItems.length,
                              itemBuilder: (context, index) {
                                final item = filteredItems[index];
                                return ProductCard(
                                  item: item,
                                  isSelected: _selectedItemId == item.id,
                                  isDisabled: controller.isVoidRequestPending,
                                  onTap: () => _openDrinkOptions(item),
                                );
                              },
                            );
                          },
                        ),
                ),

                // Bottom Category Bar (Strictly synced with Admin Categories)
                if (!keyboardOpen)
                  Container(
                    height: 54,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF9FAFB),
                      border: Border(
                        top: BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                    ),
                    child: ReorderableListView.builder(
                      scrollDirection: Axis.horizontal,
                      buildDefaultDragHandles: false,
                      onReorder: controller.reorderCategories,
                      itemCount: controller.categories.length,
                      itemBuilder: (context, index) {
                        final cat = controller.categories[index];
                        final isSelected = controller.selectedCategory == cat;
                        return ReorderableDelayedDragStartListener(
                          key: ValueKey(cat),
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InkWell(
                              onTap: () => controller.setCategory(cat),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color:
                                      isSelected ? Colors.black : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.black
                                        : const Color(0xFFD1D5DB),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    cat,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.normal,
                                      color: isSelected
                                          ? Colors.white
                                          : const Color(0xFF111827),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // Mobile/Narrow Checkout Summary Bar
                if (!isWide && !keyboardOpen)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$cartItemCount ${cartItemCount == 1 ? "item" : "items"} in cart',
                                  style: const TextStyle(
                                      fontSize: 12, color: Color(0xFF6B7280)),
                                ),
                                Text(
                                  '₱${currency.format(controller.total)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _openMobileCartSheet,
                            icon: const Icon(Icons.shopping_bag_outlined,
                                size: 18),
                            label: const Text('Checkout'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );

          if (!isWide) {
            return menuSection;
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: ClipRect(child: menuSection)),
              SizedBox(
                width: checkoutPanelWidth,
                child: CartPanel(
                  panelWidth: checkoutPanelWidth,
                  controller: controller,
                  dineInEnabled: sync.hasPermission('dineIn'),
                  takeOutEnabled: sync.hasPermission('takeOut'),
                  isKeyboardOpen: keyboardOpen,
                  onProceedOrder: _handleProceedOrder,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
