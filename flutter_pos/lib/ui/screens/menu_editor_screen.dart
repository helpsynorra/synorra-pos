import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/menu_item.dart';
import '../../services/menu_image_store.dart';
import '../../state/pos_controller.dart';
import '../widgets/menu_item_image.dart';
import '../widgets/pos_app_bar.dart';
import '../widgets/pos_navigation_drawer.dart';

// Shared design tokens for the menu editor and its item modal.
const Color _navy = Color(0xFF0F172A);
const Color _ink = Color(0xFF111827);
const Color _subtle = Color(0xFF6B7280);
const Color _line = Color(0xFFE5E7EB);
const Color _canvas = Color(0xFFF5F6F8);
const Color _fieldFill = Color(0xFFF9FAFB);
const Color _success = Color(0xFF16A34A);
const Color _successSoft = Color(0xFFDCFCE7);
const Color _successInk = Color(0xFF15803D);

BoxDecoration _cardBox() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _line),
    );

InputDecoration _inputDecoration(
  String hint, {
  String? prefixText,
  TextStyle? prefixStyle,
  String? errorText,
  EdgeInsetsGeometry? contentPadding,
  Color fillColor = _fieldFill,
}) {
  const radius = BorderRadius.all(Radius.circular(12));
  return InputDecoration(
    hintText: hint,
    prefixText: prefixText,
    prefixStyle: prefixStyle,
    errorText: errorText,
    filled: true,
    fillColor: fillColor,
    isDense: true,
    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
    contentPadding: contentPadding ??
        const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    border: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: _line),
    ),
    enabledBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: _line),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: _navy, width: 1.5),
    ),
    errorBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: Color(0xFFDC2626)),
    ),
    focusedErrorBorder: const OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: Color(0xFFDC2626), width: 1.5),
    ),
  );
}

String? _typeForCategory(Map<String, String> categoryTypes, String category) {
  final key = category.trim().toLowerCase();
  for (final entry in categoryTypes.entries) {
    if (entry.key.trim().toLowerCase() == key) return entry.value;
  }
  return null;
}

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

  bool get _canAddCategory {
    final type = _newCategoryType;
    final hasType = type != null &&
        (type != 'Other' ||
            _customCategoryTypeController.text.trim().isNotEmpty);
    return hasType && _categoryController.text.trim().isNotEmpty;
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

  Future<void> _showManageCategories() async {
    while (true) {
      if (!mounted) return;
      final categories = widget.controller.categories
          .where((entry) => entry != 'All')
          .toList();
      final categoryTypes = widget.controller.localStorage.getCategoryTypes();
      final action = await showDialog<_CategoryAction>(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Manage Categories',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Edit a category name or its type. The type is what the admin panel shows under Sold Products.',
                      style: TextStyle(
                          fontSize: 12.5, color: _subtle, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    if (categories.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          'No categories yet. Add one above.',
                          style: TextStyle(color: _subtle),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: categories.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final category = categories[index];
                            final type =
                                _typeForCategory(categoryTypes, category);
                            final count = widget.controller.menu
                                .where((item) =>
                                    item.category.trim().toLowerCase() ==
                                    category.toLowerCase())
                                .length;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              onTap: () => Navigator.pop(
                                dialogContext,
                                _CategoryAction.edit(category),
                              ),
                              title: Text(
                                category,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _ink,
                                ),
                              ),
                              subtitle: Text(
                                '${type == null || type.trim().isEmpty ? 'No type' : type} · '
                                '$count item${count == 1 ? '' : 's'}',
                                style: const TextStyle(
                                    fontSize: 12, color: _subtle),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Edit $category',
                                    onPressed: () => Navigator.pop(
                                      dialogContext,
                                      _CategoryAction.edit(category),
                                    ),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 19,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete $category',
                                    onPressed: () => Navigator.pop(
                                      dialogContext,
                                      _CategoryAction.delete(category),
                                    ),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 19,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      if (action == null || !mounted) return;
      if (action.delete) {
        await _deleteCategory(action.category);
      } else {
        await _editCategory(action.category);
      }
    }
  }

  Future<void> _editCategory(String category) async {
    final categoryTypes = widget.controller.localStorage.getCategoryTypes();
    final currentType = _typeForCategory(categoryTypes, category);
    final otherNames = widget.controller.categories
        .where((entry) =>
            entry != 'All' && entry.toLowerCase() != category.toLowerCase())
        .toList();

    final draft = await showDialog<_CategoryDraft>(
      context: context,
      builder: (_) => _CategoryEditorDialog(
        initialName: category,
        initialType: currentType,
        otherNames: otherNames,
      ),
    );
    if (draft == null || !mounted) return;

    final newName = draft.name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final newType = draft.type.trim();
    if (newName.isEmpty || newType.isEmpty) return;

    final nextCategories = List<String>.from(widget.controller.categories);
    final nameIndex = nextCategories
        .indexWhere((entry) => entry.toLowerCase() == category.toLowerCase());
    if (nameIndex >= 0) {
      nextCategories[nameIndex] = newName;
    } else {
      nextCategories.add(newName);
    }

    final nextTypes = Map<String, String>.from(categoryTypes)
      ..removeWhere((key, _) =>
          key.toLowerCase() == category.toLowerCase() ||
          key.toLowerCase() == newName.toLowerCase());
    nextTypes[newName] = newType;
    await widget.controller.localStorage.saveCategoryTypes(nextTypes);

    final nextMenu = <MenuItem>[
      for (final item in widget.controller.menu)
        if (item.category.trim().toLowerCase() == category.toLowerCase())
          MenuItem(
            id: item.id,
            name: item.name,
            price: item.price,
            category: newName,
            categoryType: newType,
            image: item.image,
            available: item.available,
            inventoryMode: item.inventoryMode,
            stockInventoryItemId: item.stockInventoryItemId,
            stockUsageAmount: item.stockUsageAmount,
            styles: item.styles,
            addons: item.addons,
            types: item.types,
          )
        else
          item,
    ];

    await widget.controller.persistMenuState(
      items: nextMenu,
      categoryList: nextCategories,
      selected: newName,
    );
    if (!mounted) return;
    setState(() => _selectedCategory = newName);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved "$newName" as $newType.'),
      ),
    );
  }

  Future<void> _showItemDialog({MenuItem? item}) async {
    final savedCategory = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => _MenuItemDialog(
        controller: widget.controller,
        item: item,
      ),
    );
    if (savedCategory != null && mounted) {
      setState(() => _selectedCategory = savedCategory);
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
    if (MenuImageStore.isLocalReference(item.image)) {
      await MenuImageStore.delete(item.image);
    }
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

  @override
  Widget build(BuildContext context) {
    final categories = widget.controller.categories;
    final categoryTypes = widget.controller.localStorage.getCategoryTypes();
    final items = _filteredItems;
    final compact = MediaQuery.sizeOf(context).width < 640;

    return Scaffold(
      backgroundColor: _canvas,
      appBar: PosAppBar(
        isVoidRequestPending: false,
        showPrintButton: false,
        syncStatus: 'Local',
        syncDotColor: _success,
        onPrint: () {},
        onSync: () => widget.controller.syncService.syncNow(),
      ),
      drawer: widget.drawerBuilder(PosSection.menu),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 24,
                24,
                compact ? 16 : 24,
                32,
              ),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Menu Items',
                            style: TextStyle(
                              fontSize: 30,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                              letterSpacing: -0.8,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Manage your products and categories',
                            style: TextStyle(fontSize: 14, color: _subtle),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => _showItemDialog(),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('Add Item'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _buildCategoriesCard(),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in categories)
                      _CategoryChip(
                        label: category,
                        selected: _selectedCategory == category,
                        onSelected: () =>
                            setState(() => _selectedCategory = category),
                        onDelete: category == 'All'
                            ? null
                            : () => _deleteCategory(category),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (items.isEmpty)
                  _buildEmptyState()
                else
                  for (final item in items) _buildItemCard(item, categoryTypes),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoriesCard() {
    final typeOptions = <String>[
      for (final type in _categoryTypes)
        if (type != 'Other') type,
    ];
    for (final type
        in widget.controller.localStorage.getCategoryTypes().values) {
      final trimmed = type.trim();
      if (trimmed.isEmpty) continue;
      if (!typeOptions
          .any((entry) => entry.toLowerCase() == trimmed.toLowerCase())) {
        typeOptions.add(trimmed);
      }
    }
    typeOptions.add('Other');
    if (_newCategoryType != null &&
        !typeOptions.any((entry) =>
            entry.toLowerCase() == _newCategoryType!.toLowerCase())) {
      typeOptions.add(_newCategoryType!);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: _cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Categories',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              TextButton(
                onPressed: _showManageCategories,
                style: TextButton.styleFrom(
                  foregroundColor: _subtle,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Manage Categories', style: TextStyle(fontSize: 13)),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _newCategoryType,
            isExpanded: true,
            decoration: _inputDecoration('Select a type first'),
            style: const TextStyle(fontSize: 13.5, color: _ink),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _subtle),
            items: typeOptions
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
            const SizedBox(height: 12),
            TextField(
              controller: _customCategoryTypeController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13.5),
              decoration: _inputDecoration('Name the custom type'),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _categoryController,
                  enabled: _newCategoryType != null,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 13.5),
                  onSubmitted: (_) {
                    if (_canAddCategory) _saveCategory();
                  },
                  decoration: _inputDecoration(
                    _newCategoryType == null
                        ? 'Select a type first'
                        : 'New category',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 52,
                height: 50,
                child: FilledButton(
                  onPressed: _canAddCategory ? _saveCategory : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Icon(Icons.add_rounded, size: 22),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 52),
      decoration: _cardBox(),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: _fieldFill,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.restaurant_menu_rounded,
                color: Color(0xFF9CA3AF), size: 26),
          ),
          const SizedBox(height: 16),
          Text(
            _selectedCategory == 'All'
                ? 'No menu items yet'
                : 'No items in $_selectedCategory',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add your first product to start selling from the POS grid.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _subtle),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => _showItemDialog(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add Item'),
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(MenuItem item, Map<String, String> categoryTypes) {
    final typeLabel =
        item.categoryType ?? categoryTypes[item.category] ?? 'Unspecified';

    final info = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 58,
            height: 58,
            color: _fieldFill,
            child: MenuItemImage(image: item.image, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${item.category} • $typeLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: _subtle),
              ),
              const SizedBox(height: 8),
              Text(
                '₱${item.price.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 34,
              child: Switch(
                value: item.available,
                onChanged: (_) => _toggleItemAvailability(item),
                activeThumbColor: Colors.white,
                activeTrackColor: _success,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFFCBD5E1),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const Text(
              'Available',
              style: TextStyle(fontSize: 10.5, color: _subtle),
            ),
          ],
        ),
        const SizedBox(width: 10),
        _SquareIconButton(
          icon: Icons.edit_outlined,
          tooltip: 'Edit ${item.name}',
          onPressed: () => _showItemDialog(item: item),
        ),
        const SizedBox(width: 8),
        _ItemActionsMenu(
          itemName: item.name,
          onEdit: () => _showItemDialog(item: item),
          onDelete: () => _deleteItem(item),
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: _cardBox(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 540;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: 10),
                    _StatusBadge(active: item.available),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [actions],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusBadge(active: item.available),
                  const SizedBox(height: 8),
                  actions,
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The shared Add / Edit Menu Item modal.
class _MenuItemDialog extends StatefulWidget {
  final PosController controller;
  final MenuItem? item;

  const _MenuItemDialog({required this.controller, this.item});

  @override
  State<_MenuItemDialog> createState() => _MenuItemDialogState();
}

class _MenuItemDialogState extends State<_MenuItemDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final List<String> _categoryOptions;
  late String _categoryValue;
  late final List<String> _selectedStyles;
  late final List<Map<String, String>> _sizeRows;
  late final List<Map<String, String>> _typeRows;
  late final List<Map<String, String>> _addOnRows;
  late String _inventoryMode;
  late bool _available;

  late String _imageRef;
  late final String _originalImageRef;
  final List<String> _createdImageRefs = <String>[];
  bool _imageBusy = false;
  bool _saving = false;
  String? _imageError;
  String? _nameError;
  String? _saveError;

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameController = TextEditingController(text: item?.name ?? '');
    _priceController = TextEditingController(
      text: item == null ? '' : item.price.toStringAsFixed(2),
    );

    final options =
        widget.controller.categories.where((entry) => entry != 'All').toList();
    final initialCategory = item?.category.trim() ?? '';
    if (initialCategory.isNotEmpty &&
        !options.any(
            (entry) => entry.toLowerCase() == initialCategory.toLowerCase())) {
      options.add(initialCategory);
    }
    _categoryOptions = options.isEmpty ? <String>['Other'] : options;
    _categoryValue = initialCategory.isNotEmpty
        ? initialCategory
        : (options.isNotEmpty ? options.first : 'Other');

    _selectedStyles = <String>[...(item?.styles ?? const <String>[])];
    _sizeRows = <Map<String, String>>[
      for (final addon in (item?.addons ?? const <MenuAddon>[]))
        if (addon.id.startsWith('size:'))
          {'name': addon.name, 'price': addon.price.toStringAsFixed(2)},
    ];
    _typeRows = <Map<String, String>>[
      for (final type in (item?.types ?? const <MenuTypeOption>[]))
        {'name': type.name, 'price': type.price.toStringAsFixed(2)},
    ];
    _addOnRows = <Map<String, String>>[
      for (final addon in (item?.addons ?? const <MenuAddon>[]))
        if (!addon.id.startsWith('size:'))
          {'name': addon.name, 'price': addon.price.toStringAsFixed(2)},
    ];
    _inventoryMode = item?.inventoryMode ?? 'none';
    _available = item?.available ?? true;

    _imageRef = item?.image ?? '';
    _originalImageRef = _imageRef;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  bool get _servesStyles {
    return !RegExp(r'^\s*(food|pastr)', caseSensitive: false)
        .hasMatch(_categoryValue);
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      setState(() {
        _imageBusy = true;
        _imageError = null;
      });
      final reference = await MenuImageStore.save(picked);
      if (!mounted) return;
      setState(() {
        _createdImageRefs.add(reference);
        _imageRef = reference;
        _imageBusy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _imageBusy = false;
        _imageError = error.toString();
      });
    }
  }

  void _removePhoto() {
    setState(() {
      _imageRef = '';
      _imageError = null;
    });
  }

  Future<void> _cancel() async {
    for (final reference in _createdImageRefs) {
      if (reference != _originalImageRef) {
        await MenuImageStore.delete(reference);
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _disposeReplacedPhotos() async {
    final keep = _imageRef.trim();
    final candidates = <String>{
      ..._createdImageRefs,
      if (MenuImageStore.isLocalReference(_originalImageRef)) _originalImageRef,
    };
    for (final reference in candidates) {
      if (reference == keep) continue;
      await MenuImageStore.delete(reference);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter a name for this item.');
      return;
    }

    setState(() {
      _saving = true;
      _nameError = null;
      _saveError = null;
    });

    try {
      final priceValue = double.tryParse(_priceController.text.trim()) ?? 0.0;
      final finalCategory =
          _categoryValue.trim().isEmpty ? 'Other' : _categoryValue.trim();

      final nextCategories = List<String>.from(widget.controller.categories);
      if (!nextCategories.any((category) =>
          category.trim().toLowerCase() == finalCategory.toLowerCase())) {
        nextCategories.add(finalCategory);
      }

      final nextAddons = <MenuAddon>[];
      for (final row in _sizeRows) {
        final label = row['name']?.trim() ?? '';
        final price = double.tryParse(row['price']?.trim() ?? '') ?? 0;
        if (label.isEmpty && price <= 0) continue;
        nextAddons.add(MenuAddon(
          id: 'size:${DateTime.now().millisecondsSinceEpoch}_${nextAddons.length}',
          name: label.isEmpty ? 'Size ${nextAddons.length + 1}' : label,
          price: price,
        ));
      }
      for (final row in _addOnRows) {
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
      for (final row in _typeRows) {
        final label = row['name']?.trim() ?? '';
        final price = double.tryParse(row['price']?.trim() ?? '') ?? 0;
        if (label.isEmpty) continue;
        nextTypes.add(MenuTypeOption(name: label, price: price));
      }

      final updatedItem = MenuItem(
        id: widget.item?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        price: priceValue,
        category: finalCategory,
        categoryType:
            widget.controller.localStorage.getCategoryTypes()[finalCategory] ??
                (widget.item?.category == finalCategory
                    ? widget.item?.categoryType
                    : null),
        image: _imageRef.trim(),
        available: _available,
        inventoryMode: _inventoryMode,
        stockInventoryItemId: widget.item?.stockInventoryItemId,
        stockUsageAmount: widget.item?.stockUsageAmount ?? 1,
        styles: _servesStyles
            ? List<String>.from(_selectedStyles)
            : const <String>[],
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
      await _disposeReplacedPhotos();
      if (!mounted) return;
      Navigator.pop(context, finalCategory);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Could not save this item. ${error.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.width < 720;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 0 : 24,
        vertical: compact ? 0 : 28,
      ),
      backgroundColor: _canvas,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 0 : 20),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 960,
          maxHeight: compact ? screen.height : screen.height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogHeader(
              title: _isEditing ? 'Edit Menu Item' : 'Add Menu Item',
              subtitle: 'Fill in the sections below, then save your changes.',
              compact: compact,
              onClose: _cancel,
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 24,
                  20,
                  compact ? 16 : 24,
                  24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDetailsSection(),
                    const SizedBox(height: 16),
                    _buildRowsSection(
                      title: 'Sizes and prices',
                      description:
                          'Add each size with its price. Leave blank to use the base price.',
                      actionLabel: 'Add size',
                      emptyLabel:
                          'No sizes added. The base price is used for a single size.',
                      nameLabel: 'Size name',
                      rows: _sizeRows,
                      defaults: const {'name': '', 'price': ''},
                    ),
                    const SizedBox(height: 16),
                    _buildRowsSection(
                      title: 'Types',
                      description:
                          'Optional choices such as iced/hot or sugar level.',
                      actionLabel: 'Add type',
                      emptyLabel: 'No types added.',
                      nameLabel: 'Type name',
                      rows: _typeRows,
                      defaults: const {'name': '', 'price': '0'},
                    ),
                    const SizedBox(height: 16),
                    _buildRowsSection(
                      title: 'Add-ons',
                      description:
                          'Optional extras with a price and stock deduction, if configured.',
                      actionLabel: 'Add add-on',
                      emptyLabel: 'No add-ons added.',
                      nameLabel: 'Add-on name',
                      rows: _addOnRows,
                      defaults: const {'name': '', 'price': '0'},
                    ),
                    const SizedBox(height: 16),
                    _buildInventorySection(),
                    if (_saveError != null) ...[
                      const SizedBox(height: 14),
                      _InlineMessage(message: _saveError!, danger: true),
                    ],
                  ],
                ),
              ),
            ),
            _DialogFooter(
              compact: compact,
              busy: _saving,
              saveLabel: _isEditing ? 'Save changes' : 'Add item',
              onCancel: _cancel,
              onSave: _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsSection() {
    return _SectionCard(
      title: 'Item Details',
      description:
          'Set the product photo, name, price, category, and serving type.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final twoColumns = width >= 520;
          final halfWidth = (width - 14) / 2;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPhotoField(),
              const SizedBox(height: 20),
              const _FieldLabel('Item Name'),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 13.5, color: _ink),
                onChanged: (_) {
                  if (_nameError != null) {
                    setState(() => _nameError = null);
                  }
                },
                decoration: _inputDecoration(
                  'e.g. Caramel Macchiato',
                  errorText: _nameError,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  SizedBox(
                    width: twoColumns ? halfWidth : width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _FieldLabel('Base Price'),
                        TextField(
                          controller: _priceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(fontSize: 13.5, color: _ink),
                          decoration: _inputDecoration(
                            '0.00',
                            prefixText: '₱ ',
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: twoColumns ? halfWidth : width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _FieldLabel('Category'),
                        DropdownButtonFormField<String>(
                          initialValue:
                              _categoryOptions.contains(_categoryValue)
                                  ? _categoryValue
                                  : _categoryOptions.first,
                          isExpanded: true,
                          decoration: _inputDecoration('Select a category'),
                          style: const TextStyle(fontSize: 13.5, color: _ink),
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: _subtle,
                          ),
                          items: _categoryOptions
                              .map((entry) => DropdownMenuItem(
                                    value: entry,
                                    child: Text(entry),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _categoryValue = value);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _FieldLabel('Type'),
              if (_servesStyles)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final style in const ['Iced', 'Hot'])
                      _StyleChip(
                        label: style,
                        selected: _selectedStyles.contains(style.toLowerCase()),
                        onSelected: () {
                          final lower = style.toLowerCase();
                          setState(() {
                            if (_selectedStyles.contains(lower)) {
                              _selectedStyles.remove(lower);
                            } else {
                              _selectedStyles.add(lower);
                            }
                          });
                        },
                      ),
                  ],
                )
              else
                const Text(
                  'Serving type applies to drinks only.',
                  style: TextStyle(fontSize: 12.5, color: _subtle),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPhotoField() {
    final hasPhoto = _imageRef.trim().isNotEmpty;

    final preview = Container(
      width: 148,
      height: 148,
      decoration: BoxDecoration(
        color: _fieldFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? MenuItemImage(
              image: _imageRef,
              fit: BoxFit.cover,
              placeholder: const _PhotoPlaceholder(),
            )
          : const _PhotoPlaceholder(),
    );

    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Product Image',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _fieldFill,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _line),
              ),
              child: const Text(
                'Stored on this device',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _subtle,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Upload a clear photo of this product. JPG, PNG, or WEBP up to 5 MB.',
          style: TextStyle(fontSize: 12, color: _subtle, height: 1.45),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _imageBusy ? null : _pickPhoto,
              icon: Icon(
                hasPhoto ? Icons.swap_horiz_rounded : Icons.upload_rounded,
                size: 18,
              ),
              label: Text(hasPhoto ? 'Replace photo' : 'Upload photo'),
              style: FilledButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (hasPhoto)
              OutlinedButton.icon(
                onPressed: _imageBusy ? null : _removePhoto,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Remove'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF475569),
                  side: const BorderSide(color: _line),
                  backgroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        if (_imageBusy) ...[
          const SizedBox(height: 12),
          const Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text(
                'Saving photo on this device…',
                style: TextStyle(fontSize: 12, color: _subtle),
              ),
            ],
          ),
        ],
        if (_imageError != null) ...[
          const SizedBox(height: 10),
          _InlineMessage(message: _imageError!, danger: true),
        ],
      ],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _fieldFill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 460) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: preview),
                const SizedBox(height: 16),
                controls,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              preview,
              const SizedBox(width: 18),
              Expanded(child: controls),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRowsSection({
    required String title,
    required String description,
    required String actionLabel,
    required String emptyLabel,
    required String nameLabel,
    required List<Map<String, String>> rows,
    required Map<String, String> defaults,
  }) {
    return _SectionCard(
      title: title,
      description: description,
      action: TextButton.icon(
        onPressed: () {
          setState(() => rows.add(Map<String, String>.from(defaults)));
        },
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(actionLabel),
        style: TextButton.styleFrom(
          foregroundColor: _navy,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      child: rows.isEmpty
          ? _EmptyHint(emptyLabel)
          : LayoutBuilder(
              builder: (context, constraints) {
                final priceWidth = constraints.maxWidth < 340 ? 74.0 : 84.0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < rows.length; index++)
                      Padding(
                        key: ObjectKey(rows[index]),
                        padding: EdgeInsets.only(
                          bottom: index == rows.length - 1 ? 0 : 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: rows[index]['name'],
                                style:
                                    const TextStyle(fontSize: 13, color: _ink),
                                decoration: _inputDecoration(
                                  nameLabel,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                ),
                                onChanged: (value) =>
                                    rows[index]['name'] = value,
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: priceWidth,
                              height: 42,
                              child: TextFormField(
                                initialValue: rows[index]['price'],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontSize: 12.5, color: _ink),
                                decoration: _inputDecoration(
                                  '0.00',
                                  prefixText: '₱',
                                  prefixStyle: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                  ),
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 11,
                                  ),
                                ),
                                onChanged: (value) =>
                                    rows[index]['price'] = value,
                              ),
                            ),
                            const SizedBox(width: 2),
                            IconButton(
                              tooltip: 'Remove row',
                              onPressed: () {
                                setState(() => rows.removeAt(index));
                              },
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                width: 32,
                                height: 32,
                              ),
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildInventorySection() {
    return _SectionCard(
      title: 'Inventory and availability',
      description:
          'Choose how this item is tracked in inventory and whether it can be sold right now.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CheckOption(
            value: _inventoryMode == 'stock_only',
            title: 'Stock only',
            subtitle: 'Deduct the selected stock item for each sale.',
            onChanged: (value) {
              setState(() {
                if (value) {
                  _inventoryMode = 'stock_only';
                } else if (_inventoryMode == 'stock_only') {
                  _inventoryMode = 'none';
                }
              });
            },
          ),
          const SizedBox(height: 10),
          _CheckOption(
            value: _inventoryMode == 'stock_and_recipe',
            title: 'Stock and recipe',
            subtitle: 'Deduct recipe ingredients and stock in one flow.',
            onChanged: (value) {
              setState(() {
                if (value) {
                  _inventoryMode = 'stock_and_recipe';
                } else if (_inventoryMode == 'stock_and_recipe') {
                  _inventoryMode = 'none';
                }
              });
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Available for sale',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Show this item on the POS product grid.',
                      style: TextStyle(fontSize: 12, color: _subtle),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _available,
                onChanged: (value) => setState(() => _available = value),
                activeThumbColor: Colors.white,
                activeTrackColor: _success,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFFCBD5E1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? description;
  final Widget? action;
  final Widget child;

  const _SectionCard({
    required this.title,
    this.description,
    this.action,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        letterSpacing: -0.1,
                      ),
                    ),
                    if (description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        description!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _subtle,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: 10),
                action!,
              ],
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool compact;
  final VoidCallback onClose;

  const _DialogHeader({
    required this.title,
    required this.subtitle,
    required this.compact,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.fromLTRB(compact ? 18 : 24, 18, compact ? 10 : 16, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 13, color: _subtle),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 20),
            style: IconButton.styleFrom(
              foregroundColor: const Color(0xFF475569),
              backgroundColor: _fieldFill,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: _line),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogFooter extends StatelessWidget {
  final bool compact;
  final bool busy;
  final String saveLabel;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _DialogFooter({
    required this.compact,
    required this.busy,
    required this.saveLabel,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.fromLTRB(compact ? 16 : 24, 14, compact ? 16 : 24, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!compact)
            const Expanded(
              child: Text(
                'Changes apply to this device.',
                style: TextStyle(fontSize: 12, color: _subtle),
              ),
            ),
          TextButton(
            onPressed: busy ? null : onCancel,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF475569),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              textStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: busy ? null : onSave,
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(saveLabel),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF374151),
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 26, color: Color(0xFF9CA3AF)),
          SizedBox(height: 6),
          Text(
            'No photo',
            style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  final String message;
  final bool danger;

  const _InlineMessage({required this.message, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFB91C1C) : _subtle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFFEF2F2) : _fieldFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: danger ? const Color(0xFFFECACA) : _line,
        ),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: 12, color: color, height: 1.4),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String message;

  const _EmptyHint(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _fieldFill,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _line),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 12.5, color: _subtle),
      ),
    );
  }
}

class _CheckOption extends StatelessWidget {
  final bool value;
  final String title;
  final String subtitle;
  final ValueChanged<bool> onChanged;

  const _CheckOption({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _fieldFill,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: value ? _navy : _line),
          ),
          child: Row(
            children: [
              Checkbox(
                value: value,
                onChanged: (next) => onChanged(next ?? false),
                activeColor: _navy,
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: _subtle),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _StyleChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      backgroundColor: Colors.white,
      selectedColor: _navy,
      side: BorderSide(color: selected ? _navy : _line),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: selected ? Colors.white : const Color(0xFF4B5563),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool active;

  const _StatusBadge({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? _successSoft : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: active ? _success : const Color(0xFF94A3B8),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            active ? 'Active' : 'Inactive',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? _successInk : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _SquareIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      style: IconButton.styleFrom(
        foregroundColor: const Color(0xFF475569),
        backgroundColor: Colors.white,
        fixedSize: const Size(40, 40),
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: const BorderSide(color: _line),
        ),
      ),
    );
  }
}

class _ItemActionsMenu extends StatelessWidget {
  final String itemName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ItemActionsMenu({
    required this.itemName,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More actions for $itemName',
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _line),
      ),
      onSelected: (value) {
        if (value == 'edit') onEdit();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'edit',
          child: _PopupRow(
            icon: Icons.edit_outlined,
            label: 'Edit item',
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: _PopupRow(
            icon: Icons.delete_outline_rounded,
            label: 'Delete item',
            danger: true,
          ),
        ),
      ],
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: _line),
        ),
        child: const Icon(
          Icons.more_vert_rounded,
          size: 20,
          color: Color(0xFF475569),
        ),
      ),
    );
  }
}

class _PopupRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;

  const _PopupRow({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFB91C1C) : const Color(0xFF1F2937);
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback? onDelete;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : const Color(0xFF4B5563);

    return Material(
      color: selected ? _navy : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? _navy : _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelected,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            14,
            9,
            onDelete == null ? 14 : 6,
            9,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: foreground,
                ),
              ),
              if (onDelete != null) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color:
                          selected ? Colors.white70 : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What the Manage Categories dialog asks the screen to do.
class _CategoryAction {
  final String category;
  final bool delete;

  const _CategoryAction.edit(this.category) : delete = false;

  const _CategoryAction.delete(this.category) : delete = true;
}

/// The name and type chosen in the category editor.
class _CategoryDraft {
  final String name;
  final String type;

  const _CategoryDraft(this.name, this.type);
}

/// Edits a category name and the type it reports to the admin panel.
class _CategoryEditorDialog extends StatefulWidget {
  final String initialName;
  final String? initialType;
  final List<String> otherNames;

  const _CategoryEditorDialog({
    required this.initialName,
    required this.initialType,
    required this.otherNames,
  });

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  static const List<String> _types = [
    'Foods',
    'Drinks',
    'Desserts',
    'Pastries',
    'Coffee',
    'Other',
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _customTypeController;
  String? _selectedType;
  String? _nameError;
  String? _typeError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _customTypeController = TextEditingController();

    final current = widget.initialType?.trim();
    if (current != null && current.isNotEmpty) {
      final match = _types.where(
        (type) => type.toLowerCase() == current.toLowerCase(),
      );
      if (match.isNotEmpty) {
        _selectedType = match.first;
      } else {
        _selectedType = 'Other';
        _customTypeController.text = current;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _customTypeController.dispose();
    super.dispose();
  }

  String get _resolvedType => _selectedType == 'Other'
      ? _customTypeController.text.trim()
      : (_selectedType ?? '').trim();

  void _save() {
    final name = _nameController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final type = _resolvedType;
    final duplicate = name.isNotEmpty &&
        widget.otherNames
            .any((entry) => entry.toLowerCase() == name.toLowerCase());

    setState(() {
      _nameError = name.isEmpty
          ? 'Enter a category name.'
          : duplicate
              ? 'That category already exists.'
              : null;
      _typeError = type.isEmpty ? 'Choose or name a type.' : null;
    });
    if (_nameError != null || _typeError != null) return;

    Navigator.pop(context, _CategoryDraft(name, type));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Edit Category',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Rename the category or change the type its sales are grouped under.',
                style: TextStyle(fontSize: 12.5, color: _subtle, height: 1.4),
              ),
              const SizedBox(height: 18),
              const _FieldLabel('Category Name'),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 13.5, color: _ink),
                onChanged: (_) {
                  if (_nameError != null) setState(() => _nameError = null);
                },
                onSubmitted: (_) => _save(),
                decoration:
                    _inputDecoration('Category name', errorText: _nameError),
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Category Type'),
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                isExpanded: true,
                decoration:
                    _inputDecoration('Select a type', errorText: _typeError),
                style: const TextStyle(fontSize: 13.5, color: _ink),
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: _subtle),
                items: _types
                    .map((type) => DropdownMenuItem(
                          value: type,
                          child: Text(type),
                        ))
                    .toList(),
                onChanged: (value) => setState(() {
                  _selectedType = value;
                  _typeError = null;
                  if (value != 'Other') _customTypeController.clear();
                }),
              ),
              if (_selectedType == 'Other') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _customTypeController,
                  style: const TextStyle(fontSize: 13.5, color: _ink),
                  onChanged: (_) {
                    if (_typeError != null) setState(() => _typeError = null);
                  },
                  onSubmitted: (_) => _save(),
                  decoration: _inputDecoration('e.g. Mama, Barako Special'),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF475569),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _navy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Save changes'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
