class InventoryItem {
  final String id;
  final String name;
  final String unit;
  final double cost;
  double stock;
  final double maxStock;
  final double? openingStock;
  final double? purchaseUnitSize;
  final double? cupUsageAmount;
  final double? cupsMake;
  final String? inventoryType;
  final String? cupSize;

  InventoryItem({
    required this.id,
    required this.name,
    this.unit = 'pcs',
    this.cost = 0.0,
    this.stock = 0.0,
    this.maxStock = 0.0,
    this.openingStock,
    this.purchaseUnitSize,
    this.cupUsageAmount,
    this.cupsMake,
    this.inventoryType,
    this.cupSize,
  });

  bool get isLowStock => maxStock > 0 && stock <= (maxStock * 0.2);

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      unit: json['unit'] as String? ?? 'pcs',
      cost: (json['cost'] as num?)?.toDouble() ?? 0.0,
      stock: (json['stock'] as num?)?.toDouble() ?? 0.0,
      maxStock: (json['maxStock'] as num?)?.toDouble() ?? (json['max_stock'] as num?)?.toDouble() ?? 0.0,
      openingStock: (json['openingStock'] as num?)?.toDouble() ?? (json['opening_stock'] as num?)?.toDouble(),
      purchaseUnitSize: (json['purchaseUnitSize'] as num?)?.toDouble() ?? (json['purchase_unit_size'] as num?)?.toDouble(),
      cupUsageAmount: (json['cupUsageAmount'] as num?)?.toDouble() ?? (json['cup_usage_amount'] as num?)?.toDouble(),
      cupsMake: (json['cupsMake'] as num?)?.toDouble() ?? (json['cups_make'] as num?)?.toDouble(),
      inventoryType: json['inventoryType'] as String? ?? json['inventory_type'] as String?,
      cupSize: json['cupSize'] as String? ?? json['cup_size'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'unit': unit,
    'cost': cost,
    'stock': stock,
    'maxStock': maxStock,
    if (openingStock != null) 'openingStock': openingStock,
    if (purchaseUnitSize != null) 'purchaseUnitSize': purchaseUnitSize,
    if (cupUsageAmount != null) 'cupUsageAmount': cupUsageAmount,
    if (cupsMake != null) 'cupsMake': cupsMake,
    if (inventoryType != null) 'inventoryType': inventoryType,
    if (cupSize != null) 'cupSize': cupSize,
  };
}
