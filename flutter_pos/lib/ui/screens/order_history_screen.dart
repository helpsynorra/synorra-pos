import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../manila_time.dart';
import '../../models/order.dart';
import '../../state/pos_controller.dart';
import '../widgets/pos_app_bar.dart';
import '../widgets/pos_navigation_drawer.dart';

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

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    _searchController.addListener(() {
      if (mounted) setState(() => _query = _searchController.text.trim().toLowerCase());
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
    final orders = widget.controller.orders.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final filtered = orders.where((order) {
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
      return order.ticketNo.toLowerCase().contains(_query) ||
          order.baristaName.toLowerCase().contains(_query) ||
          order.items.any((item) => item.name.toLowerCase().contains(_query));
    }).toList();
    final online = widget.controller.syncService.isOnline;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: PosAppBar(
        isVoidRequestPending: widget.controller.isVoidRequestPending,
        showPrintButton: false,
        syncStatus: online ? 'Online' : 'Offline',
        syncDotColor: online ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF),
        onPrint: () {},
        onSync: () => widget.controller.syncService.syncAll(),
      ),
      drawer: widget.drawerBuilder(PosSection.orderHistory),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Order History', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, color: _navy)),
                const SizedBox(height: 5),
                Text('${orders.length} orders saved on this device${online ? '' : ' · Available offline'}',
                    style: const TextStyle(color: Color(0xFF71819B), fontSize: 13)),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search ticket, item, or cashier',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE3E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE3E8F0))),
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
                ? Center(child: Text(orders.isEmpty ? 'No orders saved on this device yet.' : 'No matching orders.', style: const TextStyle(color: Color(0xFF71819B))))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) => _orderCard(filtered[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _orderCard(Order order) {
    final date = ManilaTime.parse(order.createdAt);
    final dateLabel = date == null ? order.createdAt : DateFormat('MMM d, y · h:mm a').format(date);
    final amount = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2).format(order.total);
    final itemCount = order.items.fold<int>(0, (sum, item) => sum + item.qty);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE8EDF4))),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetails(order),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(order.ticketNo.isEmpty ? 'Order ${order.id}' : 'Ticket ${order.ticketNo}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _navy))),
              Text(amount, style: const TextStyle(fontWeight: FontWeight.w700, color: _navy)),
            ]),
            const SizedBox(height: 7),
            Text(dateLabel, style: const TextStyle(fontSize: 12, color: Color(0xFF71819B))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Text('$itemCount items', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF53647F), fontSize: 13))),
              _badge(order.voided ? 'VOIDED' : (order.isSynced ? 'SAVED' : 'NOT SAVED'), order.voided ? const Color(0xFFFFEEEE) : const Color(0xFFEAF2FF), order.voided ? const Color(0xFFB42332) : _navy),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _badge(String label, Color background, Color foreground) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: foreground)),
      );

  void _showDetails(Order order) {
    final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(order.ticketNo.isEmpty ? 'Order details' : 'Ticket ${order.ticketNo}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: _navy)),
            const SizedBox(height: 4),
            Text('${order.baristaName} · ${order.paymentMethod.toUpperCase()} · ${order.serviceMode}', style: const TextStyle(color: Color(0xFF71819B))),
            const Divider(height: 24),
            Flexible(child: ListView(shrinkWrap: true, children: [
              for (final item in order.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text('${item.qty}× ${item.name}${item.optionsSummary.isEmpty ? '' : '\n${item.optionsSummary}'}')),
                    Text(currency.format(item.lineTotal)),
                  ]),
                ),
            ])),
            const Divider(height: 24),
            _totalRow('Subtotal', currency.format(order.subtotal)),
            if (order.discount > 0) _totalRow('Discount', '-${currency.format(order.discount)}'),
            _totalRow('Total', currency.format(order.total), bold: true),
            _totalRow('Paid · Change', '${currency.format(order.paid)} · ${currency.format(order.change)}'),
            if (order.voided && order.voidReason != null) ...[
              const SizedBox(height: 8),
              Text('Void reason: ${order.voidReason}', style: const TextStyle(color: Color(0xFFB42332))),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.normal))),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.normal, color: bold ? _navy : null)),
        ]),
      );
}
