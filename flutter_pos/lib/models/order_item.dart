class OrderAddonSelection {
  final String? id;
  final String name;
  final int qty;
  final double price;
  final String? inventoryItemId;
  final double? usageAmount;
  final String? usageUnit;

  const OrderAddonSelection({
    this.id,
    required this.name,
    this.qty = 1,
    required this.price,
    this.inventoryItemId,
    this.usageAmount,
    this.usageUnit,
  });

  factory OrderAddonSelection.fromJson(Map<String, dynamic> json) {
    return OrderAddonSelection(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      qty: (json['qty'] as num?)?.toInt() ?? 1,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      inventoryItemId: json['inventoryItemId'] as String? ?? json['inventory_item_id'] as String?,
      usageAmount: (json['usageAmount'] as num?)?.toDouble() ?? (json['usage_amount'] as num?)?.toDouble(),
      usageUnit: json['usageUnit'] as String? ?? json['usage_unit'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'qty': qty,
    'price': price,
    if (inventoryItemId != null) 'inventoryItemId': inventoryItemId,
    if (usageAmount != null) 'usageAmount': usageAmount,
    if (usageUnit != null) 'usageUnit': usageUnit,
  };
}

class OrderItem {
  final String productId;
  final String name;
  int qty;
  final double price;
  final String? style; // 'hot' or 'iced'
  final List<OrderAddonSelection> addons;
  final String? category;
  final String? categoryType;
  final String? serviceMode;

  OrderItem({
    required this.productId,
    required this.name,
    this.qty = 1,
    required this.price,
    this.style,
    this.addons = const [],
    this.category,
    this.categoryType,
    this.serviceMode,
  });

  double get unitPrice {
    double addonsTotal = addons.fold(0.0, (sum, a) => sum + (a.price * a.qty));
    return price + addonsTotal;
  }

  double get lineTotal => unitPrice * qty;

  String get optionsSummary {
    final parts = <String>[];
    if (style != null && style!.isNotEmpty) {
      parts.add(style == 'hot' ? 'Hot' : 'Iced');
    }
    for (final addon in addons) {
      final quantityLabel = addon.qty > 1 ? '${addon.qty}× ${addon.name}' : addon.name;
      final addonTotal = addon.price * addon.qty;
      final priceLabel = addonTotal > 0
          ? ' (+₱${addonTotal.toStringAsFixed(addonTotal.truncateToDouble() == addonTotal ? 0 : 2)})'
          : '';
      parts.add('$quantityLabel$priceLabel');
    }
    return parts.join(', ');
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    List<OrderAddonSelection> parsedAddons = [];
    if (json['addons'] is List) {
      parsedAddons = (json['addons'] as List)
          .whereType<Map>()
          .map((e) => OrderAddonSelection.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return OrderItem(
      productId: json['productId'] as String? ?? json['product_id_snapshot'] as String? ?? '',
      name: json['name'] as String? ?? json['name_snapshot'] as String? ?? '',
      qty: (json['qty'] as num?)?.toInt() ?? 1,
      price: (json['price'] as num?)?.toDouble() ?? (json['price_snapshot'] as num?)?.toDouble() ?? 0.0,
      style: json['style'] as String?,
      addons: parsedAddons,
      category: json['category'] as String?,
      categoryType: json['categoryType'] as String? ?? json['category_type'] as String?,
      serviceMode: json['serviceMode'] as String? ?? json['service_mode'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'name': name,
    'qty': qty,
    'price': price,
    if (style != null) 'style': style,
    'addons': addons.map((a) => a.toJson()).toList(),
    if (category != null) 'category': category,
    if (categoryType != null) 'categoryType': categoryType,
    if (serviceMode != null) 'serviceMode': serviceMode,
  };
}
