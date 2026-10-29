import 'package:flutter/material.dart';

import '../../models/menu_item.dart';
import '../../state/pos_controller.dart';
import '../widgets/pos_app_bar.dart';
import '../widgets/pos_navigation_drawer.dart';

class MenuEditorScreen extends StatefulWidget {
  final PosController controller;
  final PosDrawerBuilder drawerBuilder;

  const MenuEditorScreen({
    super.key,
    required this.controller,
    required this.drawerBuilder,
  });

  @override
  State<MenuEditorScreen> createState() => _MenuEditorScreenState();
}

class _MenuEditorScreenState extends State<MenuEditorScreen> {
  static const List<String> _categoryTypes = [
    'Foods',
    'Drinks',
    'Desserts',
    'Pastries',
    'Coffee',
    'Other',
  ];

  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _customCategoryTypeController =
      TextEditingController();
  String? _newCategoryType;
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _selectedCategory = widget.controller.selectedCategory;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _categoryController.dispose();
    _customCategoryTypeController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  List<MenuItem> get _filteredItems {
    final items = widget.controller.menu.where((item) {
      if (_selectedCategory == 'All') return true;
      return item.category.trim().toLowerCase() ==
          _selectedCategory.trim().toLowerCase();
    }).toList();

    items.sort((a, b) {
      final byCategory =
          a.category.toLowerCase().compareTo(b.category.toLowerCase());
      if (byCategory != 0) return byCategory;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  }

  Future<void> _persistMenu() async {
    await widget.controller.localStorage.saveMenu(widget.controller.menu);
    widget.controller.refreshLocalMenuState();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _saveCategory() async {
    final value = _categoryController.text.trim();
    final selectedType = _newCategoryType;
    final type = selectedType == 'Other'
        ? _customCategoryTypeController.text.trim()
        : selectedType;
    if (value.isEmpty || type == null || type.isEmpty) return;

    final normalized = value.replaceAll(RegExp(r'\s+'), ' ');
    final exists = widget.controller.categories.any((category) =>
        category.trim().toLowerCase() == normalized.toLowerCase());
    if (!exists) {
      final nextCategories = List<String>.from(widget.controller.categories)
        ..add(normalized);
      await widget.controller.persistMenuState(
        categoryList: nextCategories,
        selected: normalized,
      );
      final categoryTypes = widget.controller.localStorage.getCategoryTypes()
        ..[normalized] = type;
      await widget.controller.localStorage.saveCategoryTypes(categoryTypes);
      if (mounted) {
        setState(() => _selectedCategory = normalized);
      }
    }
    _categoryController.clear();
    _customCategoryTypeController.clear();
    if (mounted) {
      setState(() {
        _newCategoryType = null;
        _selectedCategory = normalized;
      });
    }
  }

  Future<void> _deleteCategory(String category) async {
    final assignedItems = widget.controller.menu
        .where((item) =>
            item.category.trim().toLowerCase() == category.trim().toLowerCase())
        .length;
    if (assignedItems > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Move or delete the $assignedItems menu item(s) in "$category" before deleting this category.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text('Delete "$category" from the menu categories?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final nextCategories = List<String>.from(widget.controller.categories)
      ..removeWhere((entry) => entry.toLowerCase() == category.toLowerCase());
    await widget.controller.persistMenuState(
      categoryList: nextCategories,
      selected: 'All',
    );
    final categoryTypes = widget.controller.localStorage.getCategoryTypes()
      ..removeWhere((name, _) => name.toLowerCase() == category.toLowerCase());
    await widget.controller.localStorage.saveCategoryTypes(categoryTypes);
    if (mounted) {
      setState(() => _selectedCategory = 'All');
    }
  }

  Future<void> _showItemDialog({MenuItem? item}) async {
    final nameController = TextEditingController(text: item?.name ?? '');
    final priceController = TextEditingController(
      text: item == null ? '' : item.price.toStringAsFixed(2),
    );
    final categoryOptions =
        widget.controller.categories.where((entry) => entry != 'All').toList();
    String categoryValue = item?.category ??
        (categoryOptions.isNotEmpty ? categoryOptions.first : 'Other');
    final selectedStyles = <String>[...(item?.styles ?? const <String>[])];
    final sizeRows = <Map<String, String>>[
      for (final addon in (item?.addons ?? const <MenuAddon>[]))
        if (addon.id.startsWith('size:'))
          {'name': addon.name, 'price': addon.price.toStringAsFixed(2)},
    ];
    final typeRows = <Map<String, String>>[
      for (final type in (item?.types ?? const <MenuTypeOption>[]))
        {'name': type.name, 'price': type.price.toStringAsFixed(2)},
    ];
    final addOnRows = <Map<String, String>>[
      for (final addon in (item?.addons ?? const <MenuAddon>[]))
        if (!addon.id.startsWith('size:'))
          {'name': addon.name, 'price': addon.price.toStringAsFixed(2)},
    ];
    String inventoryMode = item?.inventoryMode ?? 'none';
    bool available = item?.available ?? true;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
              child: SizedBox(
                width: 900,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Edit menu item',
                                  style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Fill in the sections below, then save your changes.',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade200),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Item details',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Set the name, category, photo, and serving style.',
                                    style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12),
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('Name',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.black87)),
                                            const SizedBox(height: 6),
                                            TextFormField(
                                              controller: nameController,
                                              decoration: const InputDecoration(
                                                hintText: 'Item name',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('Base price',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.black87)),
                                            const SizedBox(height: 6),
                                            TextFormField(
                                              controller: priceController,
                                              keyboardType: const TextInputType
                                                  .numberWithOptions(
                                                  decimal: true),
                                              decoration: const InputDecoration(
                                                hintText: '0.00',
                                                border: OutlineInputBorder(),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('Category',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.black87)),
                                            const SizedBox(height: 6),
                                            DropdownButtonFormField<String>(
                                              initialValue: categoryOptions
                                                      .contains(categoryValue)
                                                  ? categoryValue
                                                  : (categoryOptions.isNotEmpty
                                                      ? categoryOptions.first
                                                      : 'Other'),
                                              decoration: const InputDecoration(
                                                border: OutlineInputBorder(),
                                              ),
                                              items: (categoryOptions.isEmpty
                                                      ? ['Other']
                                                      : categoryOptions)
                                                  .map((entry) =>
                                                      DropdownMenuItem<String>(
                                                        value: entry,
                                                        child: Text(entry),
                                                      ))
                                                  .toList(),
                                              onChanged: (value) {
                                                if (value != null) {
                                                  categoryValue = value;
                                                  setDialogState(() {});
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    children: [
                                      const Text('Type',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.black87)),
                                      const Spacer(),
                                      Row(
                                        children: ['Iced', 'Hot']
                                            .map(
                                              (style) => Padding(
                                                padding: const EdgeInsets.only(
                                                    left: 8),
                                                child: ChoiceChip(
                                                  label: Text(style),
                                                  selected:
                                                      selectedStyles.contains(
                                                          style.toLowerCase()),
                                                  onSelected: (_) {
                                                    final lower =
                                                        style.toLowerCase();
                                                    if (selectedStyles
                                                        .contains(lower)) {
                                                      selectedStyles
                                                          .remove(lower);
                                                    } else {
                                                      selectedStyles.add(lower);
                                                    }
                                                    setDialogState(() {});
                                                  },
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade200),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Sizes and prices',
                                          style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: () {
                                          sizeRows
                                              .add({'name': '', 'price': ''});
                                          setDialogState(() {});
                                        },
                                        icon: const Icon(Icons.add_rounded),
                                        label: const Text('Add size'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Add each size with its price. Leave blank to use the base price.',
                                    style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12),
                                  ),
                                  const SizedBox(height: 10),
                                  if (sizeRows.isEmpty)
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 12),
                                      child: Text(
                                          'No sizes added. Use the base price above for a single price.',
                                          style: TextStyle(color: Colors.grey)),
                                    )
                                  else
                                    ...sizeRows.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final row = entry.value;
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                initialValue: row['name'],
                                                decoration:
                                                    const InputDecoration(
                                                        labelText: 'Size name'),
                                                onChanged: (value) =>
                                                    row['name'] = value,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            SizedBox(
                                              width: 160,
                                              child: TextFormField(
                                                initialValue: row['price'],
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                        decimal: true),
                                                decoration:
                                                    const InputDecoration(
                                                        labelText: 'Price'),
                                                onChanged: (value) =>
                                                    row['price'] = value,
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () {
                                                sizeRows.removeAt(index);
                                                setDialogState(() {});
                                              },
                                              icon: const Icon(
                                                  Icons.delete_outline_rounded),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade200),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Types',
                                          style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: () {
                                          typeRows
                                              .add({'name': '', 'price': '0'});
                                          setDialogState(() {});
                                        },
                                        icon: const Icon(Icons.add_rounded),
                                        label: const Text('Add type'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Optional choices like iced/hot or sugar level.',
                                    style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12),
                                  ),
                                  const SizedBox(height: 10),
                                  if (typeRows.isEmpty)
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 12),
                                      child: Text('No types added.',
                                          style: TextStyle(color: Colors.grey)),
                                    )
                                  else
                                    ...typeRows.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final row = entry.value;
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                initialValue: row['name'],
                                                decoration:
                                                    const InputDecoration(
                                                        labelText: 'Type name'),
                                                onChanged: (value) =>
                                                    row['name'] = value,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            SizedBox(
                                              width: 160,
                                              child: TextFormField(
                                                initialValue: row['price'],
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                        decimal: true),
                                                decoration:
                                                    const InputDecoration(
                                                        labelText: 'Price'),
                                                onChanged: (value) =>
                                                    row['price'] = value,
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () {
                                                typeRows.removeAt(index);
                                                setDialogState(() {});
                                              },
                                              icon: const Icon(
                                                  Icons.delete_outline_rounded),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade200),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Add-ons',
                                          style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: () {
                                          addOnRows
                                              .add({'name': '', 'price': '0'});
                                          setDialogState(() {});
                                        },
                                        icon: const Icon(Icons.add_rounded),
                                        label: const Text('Add add-on'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Optional extras with price and stock deduction, if configured.',
                                    style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12),
                                  ),
                                  const SizedBox(height: 10),
                                  if (addOnRows.isEmpty)
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 12),
                                      child: Text('No add-ons added.',
                                          style: TextStyle(color: Colors.grey)),
                                    )
                                  else
                                    ...addOnRows.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final row = entry.value;
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                initialValue: row['name'],
                                                decoration:
                                                    const InputDecoration(
                                                        labelText:
                                                            'Add-on name'),
                                                onChanged: (value) =>
                                                    row['name'] = value,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            SizedBox(
                                              width: 160,
                                              child: TextFormField(
                                                initialValue: row['price'],
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                        decimal: true),
                                                decoration:
                                                    const InputDecoration(
                                                        labelText: 'Price'),
                                                onChanged: (value) =>
                                                    row['price'] = value,
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () {
                                                addOnRows.removeAt(index);
                                                setDialogState(() {});
                                              },
                                              icon: const Icon(
                                                  Icons.delete_outline_rounded),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade200),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Inventory and availability',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Choose how this item is tracked in inventory and whether it is currently available.',
                                    style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12),
                                  ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: [
                                      SizedBox(
                                        width: 260,
                                        child: CheckboxListTile(
                                          value: inventoryMode == 'stock_only',
                                          onChanged: (value) {
                                            if (value == true) {
                                              inventoryMode = 'stock_only';
                                            } else if (inventoryMode ==
                                                'stock_only') {
                                              inventoryMode = 'none';
                                            }
                                            setDialogState(() {});
                                          },
                                          title: const Text('Stock only'),
                                          subtitle: const Text(
                                              'Deduct selected stock item for each sale.'),
                                          controlAffinity:
                                              ListTileControlAffinity.leading,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 300,
                                        child: CheckboxListTile(
                                          value: inventoryMode ==
                                              'stock_and_recipe',
                                          onChanged: (value) {
                                            if (value == true) {
                                              inventoryMode =
                                                  'stock_and_recipe';
                                            } else if (inventoryMode ==
                                                'stock_and_recipe') {
                                              inventoryMode = 'none';
                                            }
                                            setDialogState(() {});
                                          },
                                          title: const Text('Stock and recipe'),
                                          subtitle: const Text(
                                              'Deduct recipe ingredients and stock in one flow.'),
                                          controlAffinity:
                                              ListTileControlAffinity.leading,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  CheckboxListTile(
                                    value: available,
                                    onChanged: (value) {
                                      if (value != null) {
                                        available = value;
                                        setDialogState(() {});
                                      }
                                    },
                                    title: const Text('Available'),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 14),
                            ),
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != true) return;

    final name = nameController.text.trim();
    final priceValue = double.tryParse(priceController.text.trim()) ?? 0.0;
    final finalCategory =
        categoryValue.trim().isEmpty ? 'Other' : categoryValue.trim();

    if (name.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item name is required.')),
        );
      }
      return;
    }

    final nextCategories = List<String>.from(widget.controller.categories);
    if (!nextCategories.any((category) =>
        category.trim().toLowerCase() == finalCategory.toLowerCase())) {
      nextCategories.add(finalCategory);
    }

    final nextAddons = <MenuAddon>[];
    for (final row in sizeRows) {
      final label = row['name']?.trim() ?? '';
      final price = double.tryParse(row['price']?.trim() ?? '') ?? 0;
      if (label.isEmpty && price <= 0) continue;
      nextAddons.add(MenuAddon(
        id: 'size:${DateTime.now().millisecondsSinceEpoch}_${nextAddons.length}',
        name: label.isEmpty ? 'Size ${nextAddons.length + 1}' : label,
        price: price,
      ));
    }
    for (final row in addOnRows) {
      final label = row['name']?.trim() ?? '';
      final price = double.tryParse(row['price']?.trim() ?? '') ?? 0;
      if (label.isEmpty) continue;
      nextAddons.add(MenuAddon(
        id: 'addon:${DateTime.now().millisecondsSinceEpoch}_${nextAddons.length}',
        name: label,
        price: price,
      ));
    }

    final nextTypes = <MenuTypeOption>[];
    for (final row in typeRows) {
      final label = row['name']?.trim() ?? '';
      final price = double.tryParse(row['price']?.trim() ?? '') ?? 0;
      if (label.isEmpty) continue;
      nextTypes.add(MenuTypeOption(name: label, price: price));
    }

    final updatedItem = MenuItem(
      id: item?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      price: priceValue,
      category: finalCategory,
      categoryType:
          widget.controller.localStorage.getCategoryTypes()[finalCategory] ??
              (item?.category == finalCategory ? item?.categoryType : null),
      image: item?.image ?? '/images/drinks.jpg',
      available: available,
      inventoryMode: inventoryMode,
      stockInventoryItemId: item?.stockInventoryItemId,
      stockUsageAmount: item?.stockUsageAmount ?? 1,
      styles: List<String>.from(selectedStyles),
      addons: nextAddons,
      types: nextTypes,
    );

    final nextMenu = List<MenuItem>.from(widget.controller.menu);
    final index = nextMenu.indexWhere((entry) => entry.id == updatedItem.id);
    if (index >= 0) {
      nextMenu[index] = updatedItem;
    } else {
      nextMenu.add(updatedItem);
    }

    await widget.controller.persistMenuState(
      items: nextMenu,
      categoryList: nextCategories,
      selected: finalCategory,
    );
    if (mounted) {
      setState(() => _selectedCategory = finalCategory);
    }
  }

  Future<void> _deleteItem(MenuItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Delete "${item.name}" from the menu?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    widget.controller.menu.removeWhere((entry) => entry.id == item.id);
    await _persistMenu();
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.controller.categories;
    final categoryTypes = widget.controller.localStorage.getCategoryTypes();
    final items = _filteredItems;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: PosAppBar(
        isVoidRequestPending: false,
        showPrintButton: false,
        syncStatus: 'Local',
        syncDotColor: const Color(0xFF22C55E),
        onPrint: () {},
        onSync: () => widget.controller.syncService.syncNow(),
      ),
      drawer: widget.drawerBuilder(PosSection.menu),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Menu Items',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _showItemDialog(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add item'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _newCategoryType,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      hintText: 'Select a type first',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: _categoryTypes
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ))
                        .toList(),
                    onChanged: (type) => setState(() {
                      _newCategoryType = type;
                      _customCategoryTypeController.clear();
                    }),
                  ),
                  if (_newCategoryType == 'Other') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _customCategoryTypeController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Custom type',
                        hintText: 'Enter a type name',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _categoryController,
                          enabled: _newCategoryType != null &&
                              (_newCategoryType != 'Other' ||
                                  _customCategoryTypeController.text
                                      .trim()
                                      .isNotEmpty),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: 'New category',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _newCategoryType != null &&
                                (_newCategoryType != 'Other' ||
                                    _customCategoryTypeController.text
                                        .trim()
                                        .isNotEmpty) &&
                                _categoryController.text.trim().isNotEmpty
                            ? _saveCategory
                            : null,
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final category in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ChoiceChip(
                            label: Text(category),
                            selected: _selectedCategory == category,
                            onSelected: (_) =>
                                setState(() => _selectedCategory = category),
                            showCheckmark: false,
                          ),
                          if (category != 'All')
                            IconButton(
                              onPressed: () => _deleteCategory(category),
                              tooltip: 'Delete $category category',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.delete_outline, size: 18),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${item.category} • ${item.categoryType ?? categoryTypes[item.category] ?? 'Unspecified'} • ₱${item.price.toStringAsFixed(2)}',
                                  style:
                                      const TextStyle(color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: item.available,
                            onChanged: (_) => _toggleItemAvailability(item),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _showItemDialog(item: item),
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit',
                          ),
                          IconButton(
                            onPressed: () => _deleteItem(item),
                            icon: const Icon(Icons.delete_outline_rounded),
                            tooltip: 'Delete',
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleItemAvailability(MenuItem item) async {
    final updated = MenuItem(
      id: item.id,
      name: item.name,
      price: item.price,
      category: item.category,
      categoryType: item.categoryType ??
          widget.controller.localStorage.getCategoryTypes()[item.category],
      image: item.image,
      available: !item.available,
      inventoryMode: item.inventoryMode,
      stockInventoryItemId: item.stockInventoryItemId,
      stockUsageAmount: item.stockUsageAmount,
      styles: item.styles,
      addons: item.addons,
      types: item.types,
    );

    final index =
        widget.controller.menu.indexWhere((entry) => entry.id == item.id);
    if (index >= 0) {
      widget.controller.menu[index] = updated;
      await _persistMenu();
    }
  }
}
