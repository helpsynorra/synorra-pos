import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../manila_time.dart';
import '../../models/order.dart';
import '../../state/pos_controller.dart';
import '../widgets/pos_app_bar.dart';
import '../widgets/pos_navigation_drawer.dart';

enum HistoryTab { orders, waste }

class OrderHistoryScreen extends StatefulWidget {
  final PosController controller;
  final PosDrawerBuilder drawerBuilder;

  const OrderHistoryScreen({
    super.key,
    required this.controller,
    required this.drawerBuilder,
  });

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  static const _navy = Color(0xFF1B2B4F);
  final _searchController = TextEditingController();
  String _query = '';
  DateTime? _selectedDate;
  HistoryTab _currentTab = HistoryTab.orders;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    _searchController.addListener(() {
      if (mounted) {
        setState(() => _query = _searchController.text.trim().toLowerCase());
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
      setState(() => _selectedDate = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allOrders = widget.controller.orders.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Exclude waste orders from regular orders view
    final sourceList = _currentTab == HistoryTab.orders
        ? allOrders.where((order) => !order.isWaste).toList()
        : allOrders.where((order) => order.isWaste).toList();

    final filtered = sourceList.where((order) {
      if (_selectedDate != null) {
        final orderDate = ManilaTime.parse(order.createdAt);
        if (orderDate == null ||
            orderDate.year != _selectedDate!.year ||
            orderDate.month != _selectedDate!.month ||
            orderDate.day != _selectedDate!.day) {
          return false;
        }
      }
      if (_query.isEmpty) return true;
      if (_currentTab == HistoryTab.orders) {
        return order.ticketNo.toLowerCase().contains(_query) ||
            order.baristaName.toLowerCase().contains(_query) ||
            order.items.any((item) => item.name.toLowerCase().contains(_query));
      } else {
        return (order.wasteReason ?? '').toLowerCase().contains(_query) ||
            order.baristaName.toLowerCase().contains(_query) ||
            order.items.any((item) => item.name.toLowerCase().contains(_query));
      }
    }).toList();

    final online = widget.controller.syncService.isOnline;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: PosAppBar(
        isVoidRequestPending: widget.controller.isVoidRequestPending,
        showPrintButton: false,
        syncStatus: online ? 'Online' : 'Offline',
        syncDotColor:
            online ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF),
        onPrint: () {},
        onSync: () => widget.controller.syncService.syncNow(),
      ),
      drawer: widget.drawerBuilder(PosSection.orderHistory),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _currentTab == HistoryTab.orders
                          ? 'Recent Orders'
                          : 'Waste Records',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: _navy),
                    ),
                    const Spacer(),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _tabPill(HistoryTab.orders, 'Orders',
                              Icons.receipt_long_outlined),
                          _tabPill(HistoryTab.waste, 'Waste Records',
                              Icons.delete_outline_rounded),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _currentTab == HistoryTab.orders
                      ? '${sourceList.length} sales orders saved on this device${online ? '' : ' · Available offline'}'
                      : '${sourceList.length} waste records with inventory deductions',
                  style:
                      const TextStyle(color: Color(0xFF71819B), fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: _currentTab == HistoryTab.orders
                        ? 'Search ticket, item, or cashier'
                        : 'Search reason, item, or cashier',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE3E8F0))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE3E8F0))),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 17),
                      label: Text(_selectedDate == null
                          ? 'Filter by date'
                          : DateFormat('MMM d, y').format(_selectedDate!)),
                    ),
                    if (_selectedDate != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => setState(() => _selectedDate = null),
                        child: const Text('Clear'),
                      ),
                    ],
                    const Spacer(),
                    Text('${filtered.length} shown',
                        style: const TextStyle(
                            color: Color(0xFF71819B), fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      sourceList.isEmpty
                          ? (_currentTab == HistoryTab.orders
                              ? 'No recent orders saved on this device.'
                              : 'No waste records yet.')
                          : 'No matching records.',
                      style: const TextStyle(color: Color(0xFF71819B)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) =>
                        _currentTab == HistoryTab.orders
                            ? _orderCard(filtered[index])
                            : _wasteCard(filtered[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tabPill(HistoryTab tab, String label, IconData icon) {
    final active = _currentTab == tab;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _currentTab = tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: active
              ? [
                  const BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 4,
                      offset: Offset(0, 1))
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16, color: active ? _navy : const Color(0xFF64748B)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? _navy : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderCard(Order order) {
    final date = ManilaTime.parse(order.createdAt);
    final dateLabel = date == null
        ? order.createdAt
        : DateFormat('MMM d, y · h:mm a').format(date);
    final amount =
        NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2)
            .format(order.total);
    final itemCount = order.items.fold<int>(0, (sum, item) => sum + item.qty);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE8EDF4))),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showOrderDetails(order),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(
                      order.ticketNo.isEmpty
                          ? 'ORDER #${order.id}'
                          : 'ORDER #${order.ticketNo.replaceFirst(RegExp(r'^#'), '')}',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _navy))),
              Text(amount,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: _navy)),
            ]),
            const SizedBox(height: 7),
            Text(dateLabel,
                style: const TextStyle(fontSize: 12, color: Color(0xFF71819B))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: Text('$itemCount items · ${order.baristaName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFF53647F), fontSize: 13))),
              _badge(
                  order.voided
                      ? 'VOIDED'
                      : (order.isSynced ? 'SAVED' : 'NOT SAVED'),
                  order.voided
                      ? const Color(0xFFFFEEEE)
                      : const Color(0xFFEAF2FF),
                  order.voided ? const Color(0xFFB42332) : _navy),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _wasteCard(Order order) {
    final date = ManilaTime.parse(order.createdAt);
    final dateLabel = date == null
        ? order.createdAt
        : DateFormat('MMM d, y · h:mm a').format(date);
    final itemCount = order.items.fold<int>(0, (sum, item) => sum + item.qty);
    final deductions =
        widget.controller.syncService.buildDeductionsForOrder(order);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFFED7AA))),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showWasteDetails(order, deductions),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline_rounded,
                        color: Color(0xFFB45309), size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        order.wasteReason?.trim().isNotEmpty == true
                            ? order.wasteReason!
                            : 'Waste Record',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF9A3412)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              _badge('WASTE', const Color(0xFFFFF4E5), const Color(0xFFB45309)),
            ]),
            const SizedBox(height: 7),
            Text(dateLabel,
                style: const TextStyle(fontSize: 12, color: Color(0xFF71819B))),
            const SizedBox(height: 10),
            Text(
              order.items.map((i) => '${i.qty}× ${i.name}').join(', '),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: _navy),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (deductions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Deducted: ${deductions.map((d) => '${d['itemName']} (-${d['amount']} ${d['unit']})').join(', ')}',
                style: const TextStyle(fontSize: 11, color: Color(0xFFB45309)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                    child: Text(
                        '$itemCount item(s) · Recorded by ${order.baristaName}',
                        style: const TextStyle(
                            color: Color(0xFF64748B), fontSize: 12))),
                _badge(
                    order.isSynced ? 'SAVED' : 'PENDING SYNC',
                    order.isSynced
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFEF3C7),
                    order.isSynced
                        ? const Color(0xFF047857)
                        : const Color(0xFFB45309)),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  Widget _badge(String label, Color background, Color foreground) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700, color: foreground)),
      );

  void _showOrderDetails(Order order) {
    final currency =
        NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    order.ticketNo.isEmpty
                        ? 'Order details'
                        : 'Order #${order.ticketNo.replaceFirst(RegExp(r'^#'), '')}',
                    style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: _navy)),
                const SizedBox(height: 4),
                Text(
                    '${order.baristaName} · ${order.paymentMethod.toUpperCase()} · ${order.serviceMode}',
                    style: const TextStyle(color: Color(0xFF71819B))),
                const Divider(height: 24),
                Flexible(
                    child: ListView(shrinkWrap: true, children: [
                  for (final item in order.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                child: Text(
                                    '${item.qty}× ${item.name}${item.optionsSummary.isEmpty ? '' : '\n${item.optionsSummary}'}')),
                            Text(currency.format(item.lineTotal)),
                          ]),
                    ),
                ])),
                const Divider(height: 24),
                _totalRow('Subtotal', currency.format(order.subtotal)),
                if (order.discount > 0)
                  _totalRow('Discount', '-${currency.format(order.discount)}'),
                _totalRow('Total', currency.format(order.total), bold: true),
                _totalRow('Paid · Change',
                    '${currency.format(order.paid)} · ${currency.format(order.change)}'),
                if (order.voided && order.voidReason != null) ...[
                  const SizedBox(height: 8),
                  Text('Void reason: ${order.voidReason}',
                      style: const TextStyle(color: Color(0xFFB42332))),
                ],
              ]),
        ),
      ),
    );
  }

  void _showWasteDetails(Order order, List<Map<String, dynamic>> deductions) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    const Icon(Icons.delete_outline_rounded,
                        color: Color(0xFFB45309), size: 24),
                    SizedBox(width: 8),
                    Text('Waste Record',
                        style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            color: _navy)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                    'Recorded by ${order.baristaName} · ${phDateTimeLabel(order.createdAt)}',
                    style: const TextStyle(
                        color: Color(0xFF71819B), fontSize: 13)),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4E5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: Row(
                    children: [
                      const Text('Reason / Note: ',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF9A3412))),
                      Expanded(
                        child: Text(
                          order.wasteReason?.trim().isNotEmpty == true
                              ? order.wasteReason!
                              : 'Waste',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFB45309)),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                const Text('Wasted Items',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _navy)),
                const SizedBox(height: 6),
                Flexible(
                    child: ListView(shrinkWrap: true, children: [
                  for (final item in order.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Text(
                          '${item.qty}× ${item.name}${item.optionsSummary.isEmpty ? '' : ' (${item.optionsSummary})'}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                ])),
                if (deductions.isNotEmpty) ...[
                  const Divider(height: 24),
                  const Text('Inventory Deductions',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _navy)),
                  const SizedBox(height: 6),
                  Flexible(
                      child: ListView(shrinkWrap: true, children: [
                    for (final deduction in deductions)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                                child: Text(
                                    deduction['itemName']?.toString() ?? '',
                                    style: const TextStyle(fontSize: 13))),
                            Text('-${deduction['amount']} ${deduction['unit']}',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFB42332))),
                          ],
                        ),
                      ),
                  ])),
                ],
                const Divider(height: 24),
                const Row(
                  children: [
                    Expanded(
                        child: Text('Sales Amount',
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFF64748B)))),
                    Text('₱0.00 (No Sale)',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B))),
                  ],
                ),
              ]),
        ),
      ),
    );
  }

  String phDateTimeLabel(String iso) {
    final parsed = ManilaTime.parse(iso);
    return parsed != null
        ? DateFormat('MMM d, y · h:mm a').format(parsed)
        : iso;
  }

  Widget _totalRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
                  color: bold ? _navy : null)),
        ]),
      );
}
