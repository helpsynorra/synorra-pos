import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../manila_time.dart';
import '../../models/menu_item.dart';
import '../../models/order.dart';
import '../../services/printer_service.dart';
import '../theme.dart';

class _ThermalSlip extends StatelessWidget {
  final String title;
  final String content;
  final double width;

  const _ThermalSlip({
    required this.title,
    required this.content,
    this.width = 220,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 1.8,
            color: SynorraTheme.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: width,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            content,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.35,
              color: Color(0xFF111111),
            ),
          ),
        ),
      ],
    );
  }
}

class slipDialog extends StatefulWidget {
  final Order order;
  final List<Order> orders;
  final List<MenuItem> menu;
  final Future<void> Function(Order order) onPrint;
  final bool internalslipEnabled;
  final bool cupLabelsEnabled;
  final bool printButtonEnabled;

  const slipDialog({
    super.key,
    required this.order,
    required this.orders,
    required this.menu,
    required this.onPrint,
    this.internalslipEnabled = true,
    this.cupLabelsEnabled = true,
    this.printButtonEnabled = true,
  });

  @override
  State<slipDialog> createState() => _slipDialogState();
}

class _slipDialogState extends State<slipDialog> {
  late String _selectedOrderId;

  @override
  void initState() {
    super.initState();
    _selectedOrderId = widget.order.id;
  }

  List<Order> get _completedOrders {
    final byId = <String, Order>{
      for (final order in widget.orders)
        if (!order.voided && !order.isWaste) order.id: order,
    };
    if (!widget.order.voided && !widget.order.isWaste) {
      byId[widget.order.id] = widget.order;
    }
    return byId.values.toList()
      ..sort((a, b) => (ManilaTime.parse(b.createdAt) ?? DateTime(0)).compareTo(
            ManilaTime.parse(a.createdAt) ?? DateTime(0),
          ));
  }

  String _orderOptionLabel(Order order) {
    final ticket = order.ticketNo.trim();
    final ticketLabel = ticket.isEmpty
        ? 'Order #${order.id}'
        : 'Order #${ticket.replaceFirst(RegExp(r'^#'), '')}';
    final date = ManilaTime.parse(order.createdAt) ?? DateTime.now();
    return '$ticketLabel · ${DateFormat('MMM d, yyyy, h:mm a').format(date)} · ₱${order.total.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final completedOrders = _completedOrders;
    final selectedOrder = completedOrders
            .where((order) => order.id == _selectedOrderId)
            .firstOrNull ??
        widget.order;
    final slipText = PrinterService.formatslip(selectedOrder);
    final labelItemIndexes =
        PrinterService.cupLabelItemIndexes(selectedOrder, widget.menu);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24))),
      backgroundColor: const Color(0xFFE5E5E5),
      child: Container(
        width: 820,
        constraints: const BoxConstraints(maxHeight: 720),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Print',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: SynorraTheme.textMain,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Order and cup-label print jobs are independent',
                        style: TextStyle(
                          fontSize: 12,
                          color: SynorraTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: const CircleBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Completed order',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: SynorraTheme.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _selectedOrderId,
              isExpanded: true,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: SynorraTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: SynorraTheme.border),
                ),
              ),
              items: completedOrders
                  .map(
                    (order) => DropdownMenuItem<String>(
                      value: order.id,
                      child: Text(
                        _orderOptionLabel(order),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (orderId) {
                if (orderId != null) {
                  setState(() => _selectedOrderId = orderId);
                }
              },
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isPhone = constraints.maxWidth < 600;
                      final panelWidth = isPhone
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 16) / 2;
                      final slipWidth =
                          (panelWidth - 28).clamp(180.0, 260.0).toDouble();

                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          if (widget.internalslipEnabled)
                            SizedBox(
                              width: panelWidth,
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 10),
                                    Center(
                                      child: _ThermalSlip(
                                        title: 'INTERNAL COPY',
                                        content: slipText,
                                        width: slipWidth,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (widget.cupLabelsEnabled)
                            SizedBox(
                              width: panelWidth,
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Cup labels',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: SynorraTheme.textMain,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDBEAFE),
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: const Text(
                                            'Ready',
                                            style: TextStyle(
                                              color: Color(0xFF1D4ED8),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    if (labelItemIndexes.isEmpty)
                                      const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 24),
                                        child: Center(
                                          child: Text(
                                            'This order has no drink labels.',
                                            style: TextStyle(
                                              color: SynorraTheme.textMuted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      )
                                    else
                                      for (var labelIndex = 0;
                                          labelIndex < labelItemIndexes.length;
                                          labelIndex++) ...[
                                        if (labelIndex > 0)
                                          const SizedBox(height: 16),
                                        Center(
                                          child: _ThermalSlip(
                                            title: 'Label ${labelIndex + 1}',
                                            content:
                                                PrinterService.formatCupLabel(
                                              selectedOrder,
                                              labelItemIndexes[labelIndex],
                                            ),
                                            width: slipWidth,
                                          ),
                                        ),
                                      ],
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SynorraTheme.primary,
                      side: const BorderSide(color: SynorraTheme.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Close'),
                  ),
                ),
                if (widget.printButtonEnabled &&
                    (widget.internalslipEnabled || widget.cupLabelsEnabled))
                  const SizedBox(width: 12),
                if (widget.printButtonEnabled &&
                    (widget.internalslipEnabled || widget.cupLabelsEnabled))
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async => widget.onPrint(selectedOrder),
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: const Text('Print'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SynorraTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
