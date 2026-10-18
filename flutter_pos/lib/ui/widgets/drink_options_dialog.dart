// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../models/menu_item.dart';
import '../../models/order_item.dart';
import '../theme.dart';

class DrinkOptionsDialog extends StatefulWidget {
  final MenuItem item;
  final Function(String? style, List<OrderAddonSelection> addons, int qty)
      onConfirm;

  const DrinkOptionsDialog({
    super.key,
    required this.item,
    required this.onConfirm,
  });

  @override
  State<DrinkOptionsDialog> createState() => _DrinkOptionsDialogState();
}

class _DrinkOptionsDialogState extends State<DrinkOptionsDialog> {
  String? _selectedStyle;
  final Map<String, int> _addonQuantities = {};
  int _qty = 1;

  @override
  void initState() {
    super.initState();
    if (widget.item.styles.isNotEmpty) {
      _selectedStyle = widget.item.styles.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizesList = widget.item.addons
        .where((addon) => addon.id.startsWith('size:'))
        .toList();
    final addonsList = widget.item.addons
        .where((addon) => !addon.id.startsWith('size:'))
        .toList();

    double extraTotal = 0;
    for (final addon in widget.item.addons) {
      final q = _addonQuantities[addon.id] ?? 0;
      final price = addon.id.startsWith('size:')
          ? addon.price - widget.item.price
          : addon.price;
      extraTotal += price * q;
    }
    final unitPrice = widget.item.price + extraTotal;
    final totalPrice = unitPrice * _qty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.item.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: SynorraTheme.textMain,
                            ),
                          ),
                          Text(
                            'Base: ₱${widget.item.price.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: SynorraTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),

                // Style Selector (Hot / Iced)
                if (widget.item.styles.isNotEmpty) ...[
                  const Text(
                    'DRINK STYLE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: SynorraTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: widget.item.styles.map((style) {
                      final isSelected = _selectedStyle == style;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: OutlinedButton(
                            onPressed: () =>
                                setState(() => _selectedStyle = style),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: isSelected
                                  ? SynorraTheme.primary
                                  : Colors.transparent,
                              foregroundColor: isSelected
                                  ? Colors.white
                                  : SynorraTheme.textMain,
                              side: BorderSide(
                                  color: isSelected
                                      ? SynorraTheme.primary
                                      : SynorraTheme.border),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: Text(
                                    style.toUpperCase(),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                // Dynamic Add-ons Section (Only shown when configured in Admin for this item)
                if (sizesList.isNotEmpty) ...[
                  const Text(
                    'SIZE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: SynorraTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...sizesList.map((size) {
                    final selected = (_addonQuantities[size.id] ?? 0) > 0;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(size.name),
                      subtitle: Text('₱${size.price.toStringAsFixed(0)}'),
                      trailing: Radio<String>(
                        value: size.id,
                        groupValue: sizesList.any((entry) => (_addonQuantities[entry.id] ?? 0) > 0)
                            ? sizesList.firstWhere((entry) => (_addonQuantities[entry.id] ?? 0) > 0).id
                            : null,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            for (final entry in sizesList) {
                              _addonQuantities.remove(entry.id);
                            }
                            _addonQuantities[value] = 1;
                          });
                        },
                      ),
                      selected: selected,
                    );
                  }),
                  const SizedBox(height: 12),
                ],

                if (addonsList.isNotEmpty) ...[
                  const Text(
                    'ADD-ONS & MODIFIERS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: SynorraTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: addonsList.length,
                      separatorBuilder: (_, __) => const Divider(height: 8),
                      itemBuilder: (context, index) {
                        final addon = addonsList[index];
                        final currentQty = _addonQuantities[addon.id] ?? 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      addon.name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      '+₱${addon.price.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: SynorraTheme.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (currentQty > 0) ...[
                                    IconButton(
                                      onPressed: () {
                                        setState(() {
                                          if (currentQty > 1) {
                                            _addonQuantities[addon.id] =
                                                currentQty - 1;
                                          } else {
                                            _addonQuantities.remove(addon.id);
                                          }
                                        });
                                      },
                                      icon: const Icon(
                                          Icons.remove_circle_outline,
                                          size: 20),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                          minWidth: 28, minHeight: 28),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6),
                                      child: Text(
                                        '$currentQty',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        final maxAllowed =
                                            addon.qtyEnabled ? addon.maxQty : 9;
                                        if (currentQty < maxAllowed) {
                                          _addonQuantities[addon.id] =
                                              currentQty + 1;
                                        }
                                      });
                                    },
                                    icon: const Icon(Icons.add_circle_outline,
                                        size: 20),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 28, minHeight: 28),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Quantity & Confirmation
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (addonsList.isNotEmpty || sizesList.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed:
                                _qty > 1 ? () => setState(() => _qty--) : null,
                            icon: const Icon(Icons.remove, size: 18),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFEEEEEE),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              '$_qty',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _qty++),
                            icon: const Icon(Icons.add, size: 18),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFEEEEEE),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: ElevatedButton(
                        onPressed: sizesList.isNotEmpty &&
                                !sizesList.any((size) =>
                                    (_addonQuantities[size.id] ?? 0) > 0)
                            ? null
                            : () {
                          final addons = <OrderAddonSelection>[];
                          _addonQuantities.forEach((id, qty) {
                            final addonDef = addonsList
                                .where((a) => a.id == id)
                                .firstOrNull;
                            final sizeDef = sizesList.where((a) => a.id == id).firstOrNull;
                            final selectedDef = addonDef ?? sizeDef;
                            if (selectedDef != null && qty > 0) {
                              addons.add(OrderAddonSelection(
                                id: selectedDef.id,
                                name: selectedDef.name,
                                qty: qty,
                                price: selectedDef.id.startsWith('size:')
                                    ? selectedDef.price - widget.item.price
                                    : selectedDef.price,
                                inventoryItemId: selectedDef.inventoryItemId,
                                usageAmount: selectedDef.usageAmount,
                                usageUnit: selectedDef.usageUnit,
                              ));
                            }
                          });
                          widget.onConfirm(_selectedStyle, addons, _qty);
                          Navigator.pop(context);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SynorraTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                        ),
                        child: Text(
                          'Add • ₱${totalPrice.toStringAsFixed(0)}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
