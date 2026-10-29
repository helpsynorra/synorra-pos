// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/menu_item.dart';
import '../../models/order.dart';
import '../../services/sync_service.dart';
import '../../state/pos_controller.dart';
import '../widgets/product_card.dart';
import '../widgets/cart_panel.dart';
import '../widgets/drink_options_dialog.dart';
import '../widgets/slip_dialog.dart';
import '../widgets/barista_shift_dialog.dart';
import '../widgets/bluetooth_printer_picker_dialog.dart';
import '../widgets/pos_navigation_drawer.dart';
import '../widgets/pos_app_bar.dart';
import '../../services/bluetooth_printer_service.dart';
import 'order_history_screen.dart';
import 'menu_editor_screen.dart';
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

  Future<void> _openMenuEditor() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MenuEditorScreen(
          controller: widget.controller,
          drawerBuilder: _buildPosDrawer,
        ),
      ),
    );
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
        role == PrinterRole.labels ? 'connectLabels' : 'connectslip';
    if (!widget.controller.syncService.hasPermission(permission)) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => BluetoothPrinterPickerDialog(role: role),
    );
  }

  Future<void> _printOrder(Order order) async {
    if (order.isWaste || order.voided) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Waste and voided records cannot be printed as sales slips.'),
          ),
        );
      }
      return;
    }

    final results = <String>[];
    final customerCopyEnabled =
        widget.controller.syncService.hasPermission('customerslip');
    if (customerCopyEnabled) {
      try {
        await _printerService.printslip(
          order,
          includeinternalCopy: customerCopyEnabled,
        );
        results.add('slip sent');
      } catch (error) {
        results.add('slip: $error');
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
        item.types.isEmpty &&
        item.styles.length == 1 &&
        item.styles.single.toLowerCase() == 'iced') {
      widget.controller.addToCart(item, style: 'iced');
      return;
    }

    if (item.styles.isNotEmpty ||
        item.addons.isNotEmpty ||
        item.types.isNotEmpty) {
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

  void _openslipDialog([Order? targetOrder]) {
    if (!widget.controller.syncService.hasPermission('printButton')) return;
    if (targetOrder?.isWaste == true || targetOrder?.voided == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Waste and voided records cannot be printed as sales slips.',
          ),
        ),
      );
      return;
    }
    final lastOrder = widget.controller.lastCompletedOrder;
    final order = targetOrder ??
        (lastOrder != null && !lastOrder.isWaste && !lastOrder.voided
            ? lastOrder
            : null) ??
        widget.controller.orders
            .where((entry) => !entry.isWaste && !entry.voided)
            .firstOrNull;
    if (order == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No orders found to print')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => SlipDialog(
        order: order,
        orders: widget.controller.orders,
        menu: widget.controller.menu,
        onPrint: _printOrder,
        internalslipEnabled:
            widget.controller.syncService.hasPermission('internalslip'),
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
        staffUsers: widget.controller.staffUsers,
        authMode: widget.controller.syncService.attendanceAuthMode,
        resolveStaffAvatarUrl:
            widget.controller.supabaseService.fetchStaffAvatarSignedUrl,
        authenticateBarista: (username, password) async {
          return widget.controller.authenticateStaffForPurpose(
            username,
            password,
            accepts: (staff) => staff.canClockShift,
          );
        },
        onPunch: (staff, type,
            {required username, required password, photoBytes}) async {
          await widget.controller.punchShift(
            staff,
            type,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${staff.name} clocked ${type == "login" ? "in" : "out"}',
              ),
            ),
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
      if (res['queued'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Order saved locally and queued for the next scheduled sync. Use Sync Now to send it sooner.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
      }
      closeMobileCheckout?.call();
      _openslipDialog(order);
    } else if (mounted && !offline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout failed: ${res['error']}')),
      );
    }
  }

  Future<void> _handleRecordWaste({VoidCallback? closeMobileCheckout}) async {
    final controller = widget.controller;
    if (controller.cart.isEmpty || controller.isProcessing) return;

    final totalWasteItems =
        controller.cart.fold<int>(0, (total, item) => total + item.qty);
    final presets = ['Spilled', 'Expired', 'Wrong Preparation', 'Damaged'];

    final selectedReason = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final reasonController = TextEditingController();
        String activePreset = '';
        String validationError = '';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              scrollable: true,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4E5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: Color(0xFFB45309), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Record Wasted Items',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Records $totalWasteItems item(s) as waste and deducts stock from inventory with no sale or payment.',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Select or enter reason / note:',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: presets.map((preset) {
                        final isSelected = activePreset == preset;
                        return ChoiceChip(
                          label: Text(preset),
                          selected: isSelected,
                          selectedColor: const Color(0xFFFEF3C7),
                          backgroundColor: const Color(0xFFF1F5F9),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? const Color(0xFF92400E)
                                : const Color(0xFF475569),
                          ),
                          onSelected: (selected) {
                            setDialogState(() {
                              activePreset = selected ? preset : '';
                              if (selected) {
                                reasonController.text = preset;
                                reasonController.selection =
                                    TextSelection.fromPosition(
                                  TextPosition(offset: preset.length),
                                );
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: reasonController,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Reason / Note *',
                        hintText:
                            'e.g. Spilled, Expired, Wrong Preparation, Damaged',
                        hintStyle: const TextStyle(
                            fontSize: 13, color: Color(0xFF94A3B8)),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        errorText:
                            validationError.isEmpty ? null : validationError,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          validationError = '';
                          if (presets.contains(value.trim())) {
                            activePreset = value.trim();
                          } else {
                            activePreset = '';
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, null),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final reason = reasonController.text.trim();
                    if (reason.isEmpty) {
                      setDialogState(() {
                        validationError = 'Enter a reason or choose a preset.';
                      });
                      return;
                    }
                    Navigator.pop(dialogContext, reason);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB42332),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Record Waste'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedReason == null || selectedReason.trim().isEmpty || !mounted) {
      return;
    }

    final stockShortfalls =
        controller.syncService.findStockShortfalls(controller.cart);
    if (stockShortfalls.isNotEmpty) {
      final number = NumberFormat('0.##');
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Insufficient inventory'),
          content: Text(stockShortfalls
              .map((item) =>
                  '${item['itemName']}: ${number.format(item['required'])} ${item['unit']} required, ${number.format(item['available'])} available')
              .join('\n')),
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

    final result =
        await controller.recordWasteOrder(reason: selectedReason.trim());
    if (!mounted) return;
    if (result['ok'] == true) {
      closeMobileCheckout?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['synced'] == true
              ? 'Waste recorded ($selectedReason) and inventory deducted.'
              : 'Waste saved ($selectedReason) locally and queued for scheduled sync.'),
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Waste was not recorded'),
          content: SingleChildScrollView(
            child: SelectableText(
              result['error']?.toString() ??
                  'The waste record could not be saved. The checkout items are still in the cart.',
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
                canRecordWaste: widget.controller.syncService
                    .hasPermission('wasteManagement'),
                isFullWidth: true,
                isKeyboardOpen: keyboardOpen,
                onProceedOrder: () => _handleProceedOrder(
                  closeMobileCheckout: () {
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                ),
                onRecordWaste: () => _handleRecordWaste(
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

  void _navigateToOrderHistory() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => OrderHistoryScreen(
          controller: widget.controller,
          drawerBuilder: _buildPosDrawer,
        ),
      ),
      (route) => route.isFirst,
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
      slipConnection: _printerService.connectionSummary(PrinterRole.slip),
      syncStatus: controller.syncService.isOnline ? 'Online' : 'Offline',
      canLogout: canLogout,
      inventoryFeaturesEnabled: controller.syncService.inventoryFeaturesEnabled,
      stockInventoryEnabled:
          controller.syncService.hasPermission('stockInventory'),
      restockInventoryEnabled:
          controller.syncService.hasPermission('restockInventory'),
      connectLabelsEnabled:
          controller.syncService.hasPermission('connectLabels'),
      connectslipEnabled: controller.syncService.hasPermission('connectslip'),
      logoutDisabledMessage: controller.isVoidRequestPending
          ? 'Wait for void approval first'
          : 'Clear checkout first',
      onOpenTerminal: _navigateToPos,
      onOpenMenuEditor: _openMenuEditor,
      onOpenOrderHistory: _navigateToOrderHistory,
      onOpenBaristas: _openBaristaShiftDialog,
      onOpenHelpCenter: _openHelpCenter,
      onConnectLabels: () => _openPrinterPicker(PrinterRole.labels),
      onConnectslip: () => _openPrinterPicker(PrinterRole.slip),
      onSync: () => controller.syncService.syncNow(),
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
        onPrint: _openslipDialog,
        onSync: () => sync.syncNow(),
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
                                  ? 'Syncing'
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
                  canRecordWaste: sync.hasPermission('wasteManagement'),
                  isKeyboardOpen: keyboardOpen,
                  onProceedOrder: _handleProceedOrder,
                  onRecordWaste: _handleRecordWaste,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
