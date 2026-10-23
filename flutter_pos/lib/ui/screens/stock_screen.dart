import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../manila_time.dart';
import '../../models/inventory_item.dart';
import '../../state/pos_controller.dart';
import '../widgets/pos_app_bar.dart';
import '../widgets/pos_navigation_drawer.dart';

class StockScreen extends StatefulWidget {
  final PosController controller;
  final PosDrawerBuilder drawerBuilder;
  final VoidCallback onPrint;
  final VoidCallback onVoid;

  const StockScreen({
    super.key,
    required this.controller,
    required this.drawerBuilder,
    required this.onPrint,
    required this.onVoid,
  });

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  static const int _inventoryPerPage = 30;
  int _visibleInventoryCount = _inventoryPerPage;
  String _filterMode = 'range';
  String _range = 'Today';
  static const List<String> _rangeOptions = [
    'Today',
    'This Week',
    'Last Week',
    'This Month',
    'Last Month',
    'This Year',
    'Last Year',
  ];
  String get _activeRange => _rangeOptions.contains(_range) ? _range : 'Today';
  String get _filterRange => _filterMode == 'date' ? 'Date' : _activeRange;
  late final TextEditingController _dateController;
  String? _editingItemId;
  Map<String, Map<String, double>>? _ledgerCache;
  String? _ledgerCacheRange;
  DateTime? _ledgerCacheDate;
  bool _ledgerLoading = true;
  int _ledgerGeneration = 0;
  String? _ledgerRequestedRange;
  DateTime? _ledgerRequestedDate;

  // Add/Edit stock item inputs (matching Admin Stock Inventory fields)
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _totalUnitController = TextEditingController();
  final TextEditingController _unitItemController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController(text: '0');
  final TextEditingController _unitController = TextEditingController();

  // Inline Restock addition map
  final Map<String, TextEditingController> _restockControllers = {};

  @override
  void initState() {
    super.initState();
    _dateController = TextEditingController(
      text: DateFormat('MM/dd/yyyy').format(ManilaTime.now()),
    );
    widget.controller.addListener(_onControllerChange);
    widget.controller.syncService.addListener(_onSyncStatusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleLedgerCalculation();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    widget.controller.syncService.removeListener(_onSyncStatusChange);
    _dateController.dispose();
    _nameController.dispose();
    _totalUnitController.dispose();
    _unitItemController.dispose();
    _qtyController.dispose();
    _unitController.dispose();
    for (final c in _restockControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onControllerChange() {
    _ledgerCache = null;
    _ledgerGeneration++;
    _ledgerLoading = false;
    _ledgerRequestedRange = null;
    _ledgerRequestedDate = null;
    if (mounted) setState(() {});
  }

  void _onSyncStatusChange() {
    if (mounted) setState(() {});
  }

  void _scheduleLedgerCalculation() {
    final range = _filterRange;
    final selectedDate = _filterMode == 'date' ? _parseSelectedDate() : null;
    if (_ledgerCache != null &&
        _ledgerCacheRange == range &&
        _ledgerCacheDate == selectedDate) {
      return;
    }
    if (_ledgerLoading &&
        _ledgerRequestedRange == range &&
        _ledgerRequestedDate == selectedDate) {
      return;
    }

    final generation = ++_ledgerGeneration;
    _ledgerLoading = true;
    _ledgerRequestedRange = range;
    _ledgerRequestedDate = selectedDate;
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (!mounted || generation != _ledgerGeneration) return;
      final ledger = widget.controller.getStockLedgers(
        widget.controller.inventory,
        range: range,
        selectedDate: selectedDate,
      );
      if (!mounted || generation != _ledgerGeneration) return;
      setState(() {
        _ledgerCache = ledger;
        _ledgerCacheRange = range;
        _ledgerCacheDate = selectedDate;
        _ledgerLoading = false;
      });
    });
  }

  String _computedCupsMakeLabel() {
    final unit = _unitController.text.trim();
    final totalUnit = double.tryParse(_totalUnitController.text.trim()) ?? 0;
    final unitItem = double.tryParse(_unitItemController.text.trim()) ?? 0;
    if (unit.isNotEmpty && totalUnit > 0 && unitItem > 0) {
      return (totalUnit / unitItem).toStringAsFixed(2);
    }
    return '—';
  }

  DateTime? _parseSelectedDate() {
    try {
      return DateFormat('MM/dd/yyyy').parseStrict(_dateController.text.trim());
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickDate() async {
    final now = ManilaTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _parseSelectedDate() ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _dateController.text = DateFormat('MM/dd/yyyy').format(selected);
      _visibleInventoryCount = _inventoryPerPage;
    });
  }

  Future<void> _handleSaveStockItem() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final pieces = double.tryParse(_qtyController.text.trim()) ?? 0;
    if (pieces < 0) return;

    final unit = _unitController.text.trim().isEmpty
        ? 'pcs'
        : _unitController.text.trim();
    final purchaseUnitSize = double.tryParse(_totalUnitController.text.trim());
    final cupUsageAmount = double.tryParse(_unitItemController.text.trim());
    final cupsMake = (unit.isNotEmpty &&
            purchaseUnitSize != null &&
            purchaseUnitSize > 0 &&
            cupUsageAmount != null &&
            cupUsageAmount > 0)
        ? (purchaseUnitSize / cupUsageAmount)
        : null;

    final pieceSize = (purchaseUnitSize != null && purchaseUnitSize > 0)
        ? purchaseUnitSize
        : 1.0;
    final baseStock = pieces * pieceSize;

    final item = InventoryItem(
      id: _editingItemId ?? 'stock-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      stock: baseStock,
      openingStock: baseStock,
      unit: unit,
      cost: 0,
      maxStock: baseStock > 0 ? baseStock : 100,
      purchaseUnitSize: (purchaseUnitSize != null && purchaseUnitSize > 0)
          ? purchaseUnitSize
          : null,
      cupUsageAmount: (cupUsageAmount != null && cupUsageAmount > 0)
          ? cupUsageAmount
          : null,
      cupsMake: cupsMake,
    );

    await widget.controller.addOrUpdateInventoryItem(item);
    _restockControllers.putIfAbsent(item.id, () => TextEditingController());
    _handleClear();
  }

  void _handleEditItem(InventoryItem item) {
    final pieceSize =
        (item.purchaseUnitSize != null && item.purchaseUnitSize! > 0)
            ? item.purchaseUnitSize!
            : 1.0;
    final pieces = (item.openingStock ?? item.stock) / pieceSize;

    setState(() {
      _editingItemId = item.id;
      _nameController.text = item.name;
      _totalUnitController.text =
          item.purchaseUnitSize != null ? item.purchaseUnitSize.toString() : '';
      _unitItemController.text =
          item.cupUsageAmount != null ? item.cupUsageAmount.toString() : '';
      _qtyController.text = pieces % 1 == 0
          ? pieces.toInt().toString()
          : pieces.toStringAsFixed(2);
      _unitController.text = item.unit;
    });
  }

  void _handleClear() {
    _editingItemId = null;
    _nameController.clear();
    _totalUnitController.clear();
    _unitItemController.clear();
    _qtyController.text = '0';
    _unitController.clear();
    setState(() {});
  }

  Future<void> _handleRestock(InventoryItem item) async {
    final controller = _restockControllers[item.id];
    if (controller == null) return;
    final pieces = double.tryParse(controller.text.trim()) ?? 0;
    if (pieces <= 0) return;

    controller.clear();
    await widget.controller.restockItem(item.id, pieces, 'Stock Restock');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added +$pieces pcs to ${item.name}')),
      );
    }
  }

  Future<void> _handleDeleteItem(InventoryItem item) async {
    final res = await widget.controller.deleteInventoryItem(item.id);
    if (res['ok'] != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(res['error']?.toString() ?? 'Could not delete item')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = widget.controller.inventory;
    final selectedDate = _filterMode == 'date' ? _parseSelectedDate() : null;
    _scheduleLedgerCalculation();
    final ledgerReady = _ledgerCache != null &&
        _ledgerCacheRange == _filterRange &&
        _ledgerCacheDate == selectedDate;
    final ledgers = ledgerReady
        ? _ledgerCache!
        : const <String, Map<String, double>>{};
    final totalCupsUsed = inventory.fold<double>(0, (total, item) {
      if (!widget.controller.isCupInventoryItem(item)) return total;
      return total + (ledgers[item.id]?['usedPerUnit'] ?? 0.0);
    });

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PosAppBar(
        sectionTitle: 'Stock inventory',
        isVoidRequestPending: widget.controller.isVoidRequestPending,
        syncStatus:
            widget.controller.syncService.isOnline ? 'Online' : 'Offline',
        syncDotColor: widget.controller.syncService.isOnline
            ? const Color(0xFF22C55E)
            : const Color(0xFF9CA3AF),
        showPrintButton: !widget.controller.syncService.printButtonHidden &&
            widget.controller.syncService.hasPermission('printButton'),
        onPrint: widget.onPrint,
        onSync: () => widget.controller.syncService.syncAll(),
      ),
      drawer: widget.drawerBuilder(PosSection.stock),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.sizeOf(context).width < 600 ? 8 : 16,
          vertical: MediaQuery.sizeOf(context).width < 600 ? 12 : 20,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          padding:
              EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Filters: Range & Date (responsive Wrap so it never overflows on narrow screens)
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'range', label: Text('Range')),
                      ButtonSegment(value: 'date', label: Text('Date')),
                    ],
                    selected: {_filterMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      setState(() {
                        _filterMode = selection.first;
                        _visibleInventoryCount = _inventoryPerPage;
                      });
                    },
                  ),
                  Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFD1D5DB)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _activeRange,
                        icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                        style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black,
                            fontWeight: FontWeight.w500),
                        items: _rangeOptions.map((r) {
                          return DropdownMenuItem(
                              value: r, child: Text('Range:  $r'));
                        }).toList(),
                        onChanged: _filterMode == 'range'
                            ? (val) {
                                if (val != null) {
                                  setState(() {
                                    _range = val;
                                    _visibleInventoryCount = _inventoryPerPage;
                                  });
                                }
                              }
                            : null,
                      ),
                    ),
                  ),
                  Container(
                    height: 38,
                    width: 190,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: _filterMode == 'date'
                          ? Colors.white
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFD1D5DB)),
                    ),
                    child: Row(
                      children: [
                        const Text('Date: ',
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFF6B7280))),
                        Expanded(
                          child: TextField(
                            controller: _dateController,
                            enabled: _filterMode == 'date',
                            readOnly: true,
                            onTap: _pickDate,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Choose date',
                          onPressed: _filterMode == 'date' ? _pickDate : null,
                          icon: const Icon(Icons.calendar_today_outlined,
                              size: 16, color: Color(0xFF4B5563)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 24, height: 30),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Metric: Total Cups Used (matches Admin box)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD1D5DB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Cups Used',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ledgerReady
                          ? '${totalCupsUsed.toStringAsFixed(2)} cups'
                          : 'Loading…',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ADD / EDIT STOCK ITEM Section
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _editingItemId != null
                          ? 'EDIT STOCK ITEM'
                          : 'ADD STOCK ITEM',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF374151),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final singleRow = constraints.maxWidth >= 960;

                        Widget field({
                          required String label,
                          required String hint,
                          required TextEditingController controller,
                          required double width,
                          required int flex,
                          bool isNumber = false,
                          bool enabled = true,
                          ValueChanged<String>? onChanged,
                        }) {
                          return _buildFormField(
                            label: label,
                            hint: hint,
                            controller: controller,
                            width: singleRow ? null : width,
                            flex: flex,
                            isNumber: isNumber,
                            enabled: enabled,
                            onChanged: onChanged,
                          );
                        }

                        final fields = [
                          field(
                            label: 'Item Name',
                            hint: 'e.g. Coffee Beans',
                            controller: _nameController,
                            width: 185,
                            flex: 3,
                          ),
                          field(
                            label: 'Total Unit Item',
                            hint: 'e.g. 1000',
                            controller: _totalUnitController,
                            width: 150,
                            flex: 2,
                            isNumber: true,
                            onChanged: (_) => setState(() {}),
                          ),
                          field(
                            label: 'Unit Item',
                            hint: 'e.g. 9',
                            controller: _unitItemController,
                            width: 140,
                            flex: 2,
                            isNumber: true,
                            onChanged: (_) => setState(() {}),
                          ),
                          field(
                            label: 'Quantity',
                            hint: '0',
                            controller: _qtyController,
                            width: 120,
                            flex: 2,
                            isNumber: true,
                          ),
                          field(
                            label: 'Unit',
                            hint: 'grams, ml, pcs',
                            controller: _unitController,
                            width: 145,
                            flex: 2,
                            onChanged: (_) => setState(() {}),
                          ),
                          field(
                            label: 'Cups make',
                            hint: '—',
                            controller: TextEditingController(
                                text: _computedCupsMakeLabel()),
                            width: 115,
                            flex: 2,
                            enabled: false,
                          ),
                        ];

                        final buttons = [
                          SizedBox(
                            height: 44,
                            child: ElevatedButton(
                              onPressed: _handleSaveStockItem,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                elevation: 0,
                              ),
                              child: Text(
                                _editingItemId != null ? 'Update' : 'Add',
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 44,
                            child: OutlinedButton(
                              onPressed: _handleClear,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black,
                                side:
                                    const BorderSide(color: Color(0xFFD1D5DB)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              child: const Text('Clear',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500)),
                            ),
                          ),
                        ];

                        if (singleRow) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (final formField in fields) ...[
                                formField,
                                const SizedBox(width: 8),
                              ],
                              ...buttons,
                            ],
                          );
                        }

                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.end,
                          children: [...fields, ...buttons],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Stock Inventory Table (Matches Admin Panel 100%)
              LayoutBuilder(
                builder: (context, constraints) {
                  final visibleInventory =
                      inventory.take(_visibleInventoryCount).toList();
                  if (!ledgerReady) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (constraints.maxWidth < 720) {
                    return Column(
                      children: visibleInventory
                          .map(
                              (item) => _buildInventoryCard(
                                item, selectedDate, ledgers[item.id] ?? const {},
                              ))
                          .toList(),
                    );
                  }
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 44,
                      dataRowMinHeight: 48,
                      dataRowMaxHeight: 54,
                      horizontalMargin: 12,
                      columnSpacing: 24,
                      headingTextStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                      columns: const [
                        DataColumn(label: Text('Item')),
                        DataColumn(label: Text('Opening')),
                        DataColumn(label: Text('Restock')),
                        DataColumn(label: Text('Used per Unit')),
                        DataColumn(label: Text('Unit')),
                        DataColumn(label: Text('Used per Pcs')),
                        DataColumn(label: Text('Remaining')),
                        DataColumn(label: Text('Cups Left')),
                        DataColumn(label: Text('Restock')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: visibleInventory.map((item) {
                        final ledger =
                            ledgers[item.id] ?? const <String, double>{};
                        final openingPcs = ledger['openingPcs'] ?? 0.0;
                        final restockedPcs = ledger['restockedPcs'] ?? 0.0;
                        final usedPerUnit = ledger['usedPerUnit'] ?? 0.0;
                        final usedPcs = ledger['usedPcs'] ?? -1.0;
                        final remainingPcs = ledger['remainingPcs'] ?? 0.0;
                        final cupsLeftVal = ledger['cupsLeft'] ?? -1.0;

                        final isPcsUnit =
                            item.unit.trim().toLowerCase() == 'pcs';
                        final cupsLeftText = (!isPcsUnit && cupsLeftVal >= 0)
                            ? '${cupsLeftVal.toStringAsFixed(1)} cups'
                            : '—';
                        final usedPerPcsText = usedPcs >= 0
                            ? '${usedPcs.toStringAsFixed(2)} pc'
                            : '—';

                        _restockControllers.putIfAbsent(
                            item.id, () => TextEditingController());
                        final rCtrl = _restockControllers[item.id]!;

                        return DataRow(
                          cells: [
                            DataCell(Text(item.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13))),
                            DataCell(Text(
                                '${openingPcs.toStringAsFixed(2)} pcs',
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF4B5563)))),
                            DataCell(Text(
                              restockedPcs > 0
                                  ? '+${restockedPcs.toStringAsFixed(2)} pcs'
                                  : '0.00 pcs',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: restockedPcs > 0
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: restockedPcs > 0
                                    ? const Color(0xFF111827)
                                    : const Color(0xFF4B5563),
                              ),
                            )),
                            DataCell(
                              Container(
                                width: 68,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0xFFD1D5DB)),
                                ),
                                child: Center(
                                  child: Text(
                                    usedPerUnit > 0
                                        ? (usedPerUnit % 1 == 0
                                            ? usedPerUnit.toInt().toString()
                                            : usedPerUnit.toStringAsFixed(2))
                                        : '0',
                                    style: const TextStyle(
                                        color: Color(0xFFDC2626),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                ),
                              ),
                            ),
                            DataCell(Text(item.unit,
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF4B5563)))),
                            DataCell(Text(usedPerPcsText,
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF4B5563)))),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 72,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: const Color(0xFFD1D5DB)),
                                    ),
                                    child: Center(
                                      child: Text(
                                        remainingPcs.toStringAsFixed(2),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text('pcs',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF6B7280))),
                                ],
                              ),
                            ),
                            DataCell(Text(cupsLeftText,
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF4B5563)))),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 64,
                                    height: 28,
                                    child: TextField(
                                      controller: rCtrl,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      style: const TextStyle(fontSize: 11),
                                      decoration: InputDecoration(
                                        hintText: '+Qty',
                                        hintStyle: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF9CA3AF)),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 0),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFD1D5DB)),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          borderSide: const BorderSide(
                                              color: Color(0xFFD1D5DB)),
                                        ),
                                      ),
                                      onSubmitted: (_) => _handleRestock(item),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    height: 28,
                                    child: ElevatedButton(
                                      onPressed: () => _handleRestock(item),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.black,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(6)),
                                        elevation: 0,
                                      ),
                                      child: const Text('Add',
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 16, color: Color(0xFF6B7280)),
                                    onPressed: () => _handleEditItem(item),
                                    constraints: const BoxConstraints(
                                        minWidth: 26, minHeight: 26),
                                    padding: EdgeInsets.zero,
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 16, color: Color(0xFF6B7280)),
                                    onPressed: () => _handleDeleteItem(item),
                                    constraints: const BoxConstraints(
                                        minWidth: 26, minHeight: 26),
                                    padding: EdgeInsets.zero,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
              if (_visibleInventoryCount < inventory.length)
                Center(
                  child: TextButton(
                    onPressed: () => setState(() {
                      _visibleInventoryCount += _inventoryPerPage;
                    }),
                    child: Text(
                      'Load more (${inventory.length - _visibleInventoryCount} remaining)',
                    ),
                  ),
                ),
              if (inventory.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: const Center(
                    child: Text(
                      'No stock inventory items configured yet.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryCard(
    InventoryItem item,
    DateTime? selectedDate,
    Map<String, double> ledger,
  ) {
    final openingPcs = ledger['openingPcs'] ?? 0.0;
    final restockedPcs = ledger['restockedPcs'] ?? 0.0;
    final usedPerUnit = ledger['usedPerUnit'] ?? 0.0;
    final remainingPcs = ledger['remainingPcs'] ?? 0.0;
    final cupsLeft = ledger['cupsLeft'] ?? -1.0;
    final isPcsUnit = item.unit.trim().toLowerCase() == 'pcs';
    final restockController = _restockControllers.putIfAbsent(
      item.id,
      () => TextEditingController(),
    );

    Widget metric(String label, String value) {
      return SizedBox(
        width: 108,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
            const SizedBox(height: 3),
            Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Edit ${item.name}',
                onPressed: () => _handleEditItem(item),
                icon: const Icon(Icons.edit_outlined, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: 'Delete ${item.name}',
                onPressed: () => _handleDeleteItem(item),
                icon: const Icon(Icons.delete_outline, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              metric('Opening', '${openingPcs.toStringAsFixed(2)} pcs'),
              metric('Restocked', '${restockedPcs.toStringAsFixed(2)} pcs'),
              metric('Used per unit',
                  '${usedPerUnit.toStringAsFixed(2)} ${item.unit}'),
              metric('Remaining', '${remainingPcs.toStringAsFixed(2)} pcs'),
              metric(
                  'Cups left',
                  isPcsUnit || cupsLeft < 0
                      ? '—'
                      : '${cupsLeft.toStringAsFixed(1)} cups'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: restockController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Restock quantity',
                    hintText: '+Qty',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _handleRestock(item),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _handleRestock(item),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(64, 46),
                ),
                child: const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required double? width,
    required int flex,
    bool enabled = true,
    bool isNumber = false,
    ValueChanged<String>? onChanged,
  }) {
    final field = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 44,
          child: TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: isNumber
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.text,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
              filled: true,
              fillColor: enabled ? Colors.white : const Color(0xFFF3F4F6),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
          ),
        ),
      ],
    );
    if (width == null) return Expanded(flex: flex, child: field);
    return SizedBox(width: width, child: field);
  }
}
