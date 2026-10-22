class MenuAddon {
  final String id;
  final String name;
  final double price;
  final bool qtyEnabled;
  final int maxQty;
  final String? inventoryItemId;
  final double? usageAmount;
  final String? usageUnit;
  final String? image;

  const MenuAddon({
    required this.id,
    required this.name,
    required this.price,
    this.qtyEnabled = false,
    this.maxQty = 9,
    this.inventoryItemId,
    this.usageAmount,
    this.usageUnit,
    this.image,
  });

  factory MenuAddon.fromJson(Map<String, dynamic> json) {
    final qtyEnabled = json['qtyEnabled'] == true || json['qty_enabled'] == true;
    return MenuAddon(
      id: json['id'] as String? ?? json['name'] as String? ?? 'addon',
      name: json['name'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      qtyEnabled: qtyEnabled,
      maxQty: (json['maxQty'] as num?)?.toInt() ?? 9,
      inventoryItemId: json['inventoryItemId'] as String? ?? json['inventory_item_id'] as String?,
      usageAmount: (json['usageAmount'] as num?)?.toDouble() ?? (json['usage_amount'] as num?)?.toDouble(),
      usageUnit: json['usageUnit'] as String? ?? json['usage_unit'] as String?,
      image: json['image'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'qtyEnabled': qtyEnabled,
    'maxQty': maxQty,
    if (inventoryItemId != null) 'inventoryItemId': inventoryItemId,
    if (usageAmount != null) 'usageAmount': usageAmount,
    if (usageUnit != null) 'usageUnit': usageUnit,
    if (image != null && image!.isNotEmpty) 'image': image,
  };
}

class MenuTypeOption {
  final String name;
  final double price;

  const MenuTypeOption({required this.name, this.price = 0});

  factory MenuTypeOption.fromJson(dynamic value) {
    if (value is Map) {
      final rawName = value['name'];
      final nestedName = rawName is Map ? rawName['name'] : rawName;
      final rawPrice = value['price'] ?? (rawName is Map ? rawName['price'] : null);
      return MenuTypeOption(
        name: nestedName?.toString() ?? '',
        price: (rawPrice as num?)?.toDouble() ?? 0,
      );
    }
    return MenuTypeOption(name: value?.toString() ?? '');
  }

  Map<String, dynamic> toJson() => {'name': name, 'price': price};
}

class MenuItem {
  final String id;
  final String name;
  final double price;
  final String category;
  final String image;
  final bool available;
  final String inventoryMode;
  final String? stockInventoryItemId;
  final double stockUsageAmount;
  final List<String> styles; // e.g. ["hot", "iced"]
  final List<MenuAddon> addons;
  final List<MenuTypeOption> types;

  const MenuItem({
    required this.id,
    required this.name,
    required this.price,
    required this.category,
    required this.image,
    this.available = true,
    this.inventoryMode = 'none',
    this.stockInventoryItemId,
    this.stockUsageAmount = 1,
    this.styles = const [],
    this.addons = const [],
    this.types = const [],
  });

  bool get isDrink => !RegExp(r'^\s*(food|pastr)', caseSensitive: false).hasMatch(category);

  static Map<String, dynamic> _parseLegacyImageOptions(String rawImage) {
    final parts = rawImage.split('#');
    final cleanImage = parts.first.isNotEmpty ? parts.first : '/images/drinks.jpg';
    final fragment = parts.length > 1 ? parts.sublist(1).join('#') : '';
    final styles = <String>[];
    final addons = <MenuAddon>[];

    if (fragment.isNotEmpty) {
      try {
        final params = Uri.splitQueryString(fragment);
        final stylesParam = params['styles'];
        if (stylesParam != null && stylesParam.isNotEmpty) {
          for (final s in stylesParam.split(',')) {
            final clean = s.trim().toLowerCase();
            if ((clean == 'hot' || clean == 'iced') && !styles.contains(clean)) {
              styles.add(clean);
            }
          }
        }
      } catch (_) {}
    }

    return {
      'image': cleanImage,
      'styles': styles,
      'addons': addons,
    };
  }

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    final rawImage = json['image'] as String? ?? '/images/drinks.jpg';
    final legacy = _parseLegacyImageOptions(rawImage);
    final category = json['category'] as String? ?? 'Other';
    final isFoodOrPastry = RegExp(r'^\s*(food|pastr)', caseSensitive: false).hasMatch(category);

    List<String> parsedStyles = [];
    final hasStoredStyles = json['styles'] is List;
    if (hasStoredStyles) {
      for (final e in (json['styles'] as List)) {
        final s = e.toString().trim().toLowerCase();
        if ((s == 'hot' || s == 'iced') && !parsedStyles.contains(s)) {
          parsedStyles.add(s);
        }
      }
    }
    if (!hasStoredStyles && (legacy['styles'] as List<String>).isNotEmpty) {
      parsedStyles = List<String>.from(legacy['styles'] as List<String>);
    }
    if (isFoodOrPastry) {
      parsedStyles = [];
    }

    // Strictly parse ONLY addons configured in the Admin panel (never fallback to hardcoded addons)
    List<MenuAddon> parsedAddons = [];
    if (json['addons'] is List) {
      for (final item in (json['addons'] as List)) {
        if (item is Map) {
          final addon = MenuAddon.fromJson(Map<String, dynamic>.from(item));
          if (addon.name.trim().isNotEmpty) {
            parsedAddons.add(addon);
          }
        }
      }
    }
    final parsedTypes = json['types'] is List
        ? (json['types'] as List)
            .map(MenuTypeOption.fromJson)
            .where((option) => option.name.trim().isNotEmpty)
            .toList()
        : <MenuTypeOption>[];

    return MenuItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Item',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      category: category,
      image: legacy['image'] as String,
      available: json['available'] != false,
      inventoryMode: json['inventoryMode']?.toString() == 'stock_only' ||
              json['inventory_mode']?.toString() == 'stock_only'
          ? 'stock_only'
          : json['inventoryMode']?.toString() == 'stock_and_recipe' ||
                  json['inventory_mode']?.toString() == 'stock_and_recipe'
              ? 'stock_and_recipe'
              : 'none',
      stockInventoryItemId: json['stockInventoryItemId']?.toString() ??
          json['stock_inventory_item_id']?.toString(),
      stockUsageAmount: (json['stockUsageAmount'] as num?)?.toDouble() ??
          (json['stock_usage_amount'] as num?)?.toDouble() ?? 1,
      styles: parsedStyles,
      addons: parsedAddons,
      types: parsedTypes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'price': price,
    'category': category,
    'image': image,
    'available': available,
    'inventoryMode': inventoryMode,
    if (stockInventoryItemId != null)
      'stockInventoryItemId': stockInventoryItemId,
    'stockUsageAmount': stockUsageAmount,
    'styles': styles,
    'addons': addons.map((a) => a.toJson()).toList(),
    'types': types.map((type) => type.toJson()).toList(),
  };
}
