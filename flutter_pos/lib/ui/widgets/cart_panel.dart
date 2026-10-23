// ignore_for_file: curly_braces_in_flow_control_structures, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../state/pos_controller.dart';

class CartPanel extends StatefulWidget {
  final PosController controller;
  final VoidCallback onProceedOrder;
  final bool isFullWidth;
  final double panelWidth;
  final bool isKeyboardOpen;
  final bool dineInEnabled;
  final bool takeOutEnabled;

  const CartPanel({
    super.key,
    required this.controller,
    required this.onProceedOrder,
    this.isFullWidth = false,
    this.panelWidth = 350,
    this.isKeyboardOpen = false,
    this.dineInEnabled = true,
    this.takeOutEnabled = true,
  });

  @override
  State<CartPanel> createState() => _CartPanelState();
}

class _SplitPaymentScreen extends StatefulWidget {
  final PosController controller;
  final String initialDigitalMethod;
  final ValueChanged<String> onDigitalMethodChanged;

  const _SplitPaymentScreen({
    required this.controller,
    required this.initialDigitalMethod,
    required this.onDigitalMethodChanged,
  });

  @override
  State<_SplitPaymentScreen> createState() => _SplitPaymentScreenState();
}

class _SplitPaymentScreenState extends State<_SplitPaymentScreen> {
  late final TextEditingController _cashController;
  late String _digitalMethod;

  @override
  void initState() {
    super.initState();
    _digitalMethod = widget.initialDigitalMethod;
    _cashController = TextEditingController(
      text: widget.controller.tenderedAmount.toInt().toString(),
    );
    widget.controller.addListener(_syncCashAmount);
  }

  void _syncCashAmount() {
    final amount = widget.controller.tenderedAmount.toInt().toString();
    if (_cashController.text != amount) _cashController.text = amount;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncCashAmount);
    _cashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final currency = NumberFormat('#,##0', 'en_PH');
    final digitalAmount =
        (controller.total - controller.tenderedAmount).clamp(0, controller.total);

    return Scaffold(
      appBar: AppBar(title: const Text('Split payment')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Total: ₱${currency.format(controller.total)}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 24),
              TextField(
                controller: _cashController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Cash portion',
                  prefixText: '₱ ',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => controller.setTenderedAmount(
                  double.tryParse(value) ?? 0,
                ),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _digitalMethod,
                decoration: const InputDecoration(
                  labelText: 'Pay remainder with',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'gcash', child: Text('GCash')),
                  DropdownMenuItem(value: 'maya', child: Text('Maya')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _digitalMethod = value);
                  widget.onDigitalMethodChanged(value);
                },
              ),
              const SizedBox(height: 16),
              Text('$_digitalMethod: ₱${currency.format(digitalAmount)}'),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromotionCodeDialog extends StatefulWidget {
  const _PromotionCodeDialog();

  @override
  State<_PromotionCodeDialog> createState() => _PromotionCodeDialogState();
}

class _PromotionCodeDialogState extends State<_PromotionCodeDialog> {
  final TextEditingController _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Promo voucher'),
      content: TextField(
        controller: _inputController,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        keyboardType: TextInputType.visiblePassword,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
        ],
        decoration: const InputDecoration(hintText: 'Enter voucher'),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _inputController.text),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _CartPanelState extends State<CartPanel> {
  static const _navy = Color(0xFF202D43);
  static const _ink = Color(0xFF14213A);
  static const _muted = Color(0xFF7A8CA8);
  static const _line = Color(0xFFE4EAF3);
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();
  bool _hasSelectedCashAmount = false;
  String? _selectedPreset;
  String _splitDigitalMethod = 'gcash';

  Future<void> _showPromotionError(String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Promo voucher'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPromotionDialog() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _PromotionCodeDialog(),
    );
    if (code == null || !mounted) return;
    final normalizedCode = code.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final matchingPromotions = widget.controller.syncService.promotionCodes.where(
      (entry) => entry['code']?.toString().trim().toUpperCase() == normalizedCode,
    );
    final promo = matchingPromotions.isEmpty ? null : matchingPromotions.first;
    if (promo != null &&
        (promo['redeemedAt'] != null || promo['redeemed_at'] != null)) {
      await _showPromotionError('Promo voucher already used.');
      return;
    }
    int? itemIndex;
    int? itemQty;
    if (promo?['discountType'] == 'item') {
      final freeItemQty = ((promo?['discountValue'] as num?)?.toInt() ?? 1).clamp(1, 99).toInt();
      final eligibleIndexes = [
        for (var index = 0; index < widget.controller.cart.length; index++)
          if (widget.controller.cart[index].qty >= freeItemQty) index,
      ];
      if (eligibleIndexes.isEmpty) {
        await _showPromotionError(
          'Add an item with quantity $freeItemQty or more.',
        );
        return;
      }
      itemIndex = await showDialog<int>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text('Choose $freeItemQty item(s) to make free'),
          children: [
            for (final index in eligibleIndexes)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, index),
                child: Text('${widget.controller.cart[index].name}  ×${widget.controller.cart[index].qty} · $freeItemQty free'),
              ),
          ],
        ),
      );
      if (itemIndex == null || !mounted) return;
      itemQty = freeItemQty;
    }
    final error = widget.controller.applyPromotionCode(code, itemIndex: itemIndex, itemQty: itemQty);
    if (error != null) {
      await _showPromotionError(error);
    } else {
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Promo voucher applied'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    _amountController.text = widget.controller.tenderedAmount > 0
        ? widget.controller.tenderedAmount.toInt().toString()
        : '0';
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant CartPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (_amountFocusNode.hasFocus) return;

    final amountText = widget.controller.paymentMethod != 'cash' &&
            !widget.controller.paymentMethod.startsWith('split')
        ? widget.controller.total.toInt().toString()
        : widget.controller.tenderedAmount.toInt().toString();
    if (_amountController.text != amountText) {
      _amountController.text = amountText;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _amountController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final currency = NumberFormat('#,##0', 'en_PH');
    final keyboardOpen =
        widget.isKeyboardOpen || MediaQuery.viewInsetsOf(context).bottom > 0;
    final isCashPayment = controller.paymentMethod == 'cash';
    final isSplitPayment = controller.paymentMethod.startsWith('split');
    final acceptsCash = isCashPayment || isSplitPayment;
    final promoApplied = controller.promoLabel != null;

    return Container(
      width: widget.isFullWidth ? double.infinity : widget.panelWidth,
      decoration: BoxDecoration(
        color: const Color(0xFFFCFDFF),
        borderRadius: widget.isFullWidth
            ? const BorderRadius.vertical(top: Radius.circular(28))
            : null,
        border: widget.isFullWidth
            ? null
            : const Border(
                left: BorderSide(color: Color(0xFFE5E7EB), width: 1),
              ),
      ),
      child: Column(
        children: [
          if (widget.isFullWidth)
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 7),
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E3),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(
              top: widget.isFullWidth ? 2 : (keyboardOpen ? 2 : 8),
              bottom: widget.isFullWidth ? 10 : (keyboardOpen ? 1 : 4),
            ),
            child: Text(
              'Checkout',
              style: TextStyle(
                fontSize: widget.isFullWidth ? 24 : (keyboardOpen ? 14 : 17),
                fontWeight: FontWeight.w700,
                color: _ink,
                letterSpacing: -.5,
              ),
            ),
          ),
          if (!keyboardOpen)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.isFullWidth ? 20 : 12,
                vertical: widget.isFullWidth ? 8 : 3,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      'NAME',
                      style: TextStyle(
                        fontSize: widget.isFullWidth ? 12 : 9,
                        fontWeight: FontWeight.w700,
                        color: _muted,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'QTY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: widget.isFullWidth ? 12 : 9,
                        fontWeight: FontWeight.w700,
                        color: _muted,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'PRICE',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: widget.isFullWidth ? 12 : 9,
                        fontWeight: FontWeight.w700,
                        color: _muted,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  if (widget.isFullWidth) const SizedBox(width: 48),
                ],
              ),
            ),
          const Divider(height: 1, color: _line),
          Expanded(
            child: controller.cart.isEmpty
                ? const SizedBox.shrink()
                : ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      scrollbars: false,
                    ),
                    child: ListView.separated(
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.isFullWidth ? 18 : 12,
                        vertical: widget.isFullWidth ? 3 : 4,
                      ),
                      itemCount: controller.cart.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: _line),
                      itemBuilder: (context, index) => Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: widget.isFullWidth ? 8 : 3,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: 4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    controller.cart[index].name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: widget.isFullWidth ? 15 : 11,
                                      color: _ink,
                                    ),
                                  ),
                                  if (controller.cart[index].optionsSummary
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Options: ${controller.cart[index].optionsSummary}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: widget.isFullWidth ? 12 : 9,
                                        color: _muted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _quantityButton(
                                    icon: Icons.remove,
                                    label:
                                        'Decrease ${controller.cart[index].name} quantity',
                                    onTap: () => controller.updateCartQty(
                                      index,
                                      controller.cart[index].qty - 1,
                                    ),
                                  ),
                                  SizedBox(
                                    width: widget.isFullWidth ? 22 : 20,
                                    child: Text(
                                      '${controller.cart[index].qty}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: widget.isFullWidth ? 15 : 10,
                                      ),
                                    ),
                                  ),
                                  _quantityButton(
                                    icon: Icons.add,
                                    label:
                                        'Increase ${controller.cart[index].name} quantity',
                                    onTap: () =>
                                        widget.controller.updateCartQty(
                                      index,
                                      controller.cart[index].qty + 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                '₱${currency.format(controller.cart[index].lineTotal)}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: widget.isFullWidth ? 14 : 11,
                                  color: _ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: widget.isFullWidth ? 18 : 12,
              vertical: widget.isFullWidth ? 12 : (keyboardOpen ? 3 : 7),
            ),
            decoration: BoxDecoration(
              color: widget.isFullWidth
                  ? const Color(0xFFF2F6FC)
                  : const Color(0xFFFCFDFF),
              border: widget.isFullWidth
                  ? null
                  : const Border(top: BorderSide(color: _line)),
              borderRadius:
                  widget.isFullWidth ? BorderRadius.circular(18) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (controller.syncService.hasPermission('promotionsEnabled') &&
                    controller.syncService.hasPermission('promotionDiscount'))
                  Row(
                    children: [
                      Expanded(
                        child: controller.promoLabel == null
                            ? TextButton.icon(
                                onPressed: controller.cart.isEmpty
                                    ? null
                                    : _showPromotionDialog,
                                icon: const Icon(Icons.local_offer_outlined, size: 17),
                                label: Text(
                                  controller.cart.isEmpty
                                      ? 'Add an item to use a promotion'
                                      : 'Apply promo voucher',
                                ),
                              )
                            : Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    size: 16,
                                    color: Color(0xFF15803D),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      'Promo ${controller.promoLabel}${controller.promoItemIndex != null ? ' · ${controller.promoItemQty ?? 1} × ${controller.cart[controller.promoItemIndex!].name} free' : ''}  −₱${currency.format(controller.discountAmount)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: _ink,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      if (controller.promoLabel != null)
                        IconButton(
                          tooltip: 'Remove promotion',
                          onPressed: controller.clearPromotion,
                          icon: const Icon(Icons.close, size: 18),
                        ),
                    ],
                  ),
                if (widget.dineInEnabled || widget.takeOutEnabled)
                  Row(
                    children: [
                      if (widget.dineInEnabled)
                        Expanded(
                          child: _buildServiceModeButton('dine-in', 'Dine In'),
                        ),
                      if (widget.dineInEnabled && widget.takeOutEnabled)
                        const SizedBox(width: 8),
                      if (widget.takeOutEnabled)
                        Expanded(
                          child:
                              _buildServiceModeButton('take-out', 'Take Out'),
                        ),
                    ],
                  ),
                SizedBox(
                    height: keyboardOpen ? 2 : (widget.isFullWidth ? 9 : 5)),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isSplitPayment ? 'Cash portion' : 'Amount',
                        style: TextStyle(
                            fontSize: widget.isFullWidth ? 18 : 12,
                            color: _ink,
                            fontWeight: widget.isFullWidth
                                ? FontWeight.w500
                                : FontWeight.normal),
                      ),
                    ),
                    SizedBox(
                      width: widget.isFullWidth ? 138 : 92,
                      height:
                          keyboardOpen ? 30 : (widget.isFullWidth ? 50 : 28),
                      child: TextField(
                        enabled: acceptsCash,
                        readOnly: true,
                        showCursor: false,
                        onTap: acceptsCash ? _openAmountKeypad : null,
                        controller: _amountController,
                        focusNode: _amountFocusNode,
                        keyboardType: TextInputType.none,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: widget.isFullWidth ? 19 : 11,
                            fontWeight: FontWeight.w700,
                            color: _ink),
                        decoration: InputDecoration(
                          prefixText: widget.isFullWidth ? '₱ ' : null,
                          prefixStyle: const TextStyle(
                            color: Color(0xFF526681),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                widget.isFullWidth ? 14 : 8),
                            borderSide:
                                const BorderSide(color: Color(0xFFD4DEEC)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                widget.isFullWidth ? 14 : 8),
                            borderSide: const BorderSide(
                                color: Color(0xFFD4DEEC), width: 1.3),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                                widget.isFullWidth ? 14 : 8),
                            borderSide: const BorderSide(
                                color: Color(0xFF5687FF), width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                    height: keyboardOpen ? 1 : (widget.isFullWidth ? 8 : 4)),
                if (widget.isFullWidth && !keyboardOpen)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Quick Cash Bills',
                      style: TextStyle(
                          color: _muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildPresetPill(
                        presetId: 'exact',
                        label: 'Exact',
                        isEnabled: acceptsCash,
                        onTap: () {
                          controller.setTenderedAmount(controller.total);
                          setState(() {
                            _hasSelectedCashAmount = true;
                            _selectedPreset = 'exact';
                            _amountController.text =
                                controller.total.toInt().toString();
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      _buildPresetPill(
                        presetId: '500',
                        label: '₱500',
                        isEnabled: acceptsCash,
                        onTap: () {
                          controller.setTenderedAmount(500);
                          setState(() {
                            _hasSelectedCashAmount = true;
                            _selectedPreset = '500';
                            _amountController.text = '500';
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      _buildPresetPill(
                        presetId: '1000',
                        label: '₱1,000',
                        isEnabled: acceptsCash,
                        onTap: () {
                          controller.setTenderedAmount(1000);
                          setState(() {
                            _hasSelectedCashAmount = true;
                            _selectedPreset = '1000';
                            _amountController.text = '1000';
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      _buildPresetPill(
                        presetId: '2000',
                        label: '₱2,000',
                        isEnabled: acceptsCash,
                        onTap: () {
                          controller.setTenderedAmount(2000);
                          setState(() {
                            _hasSelectedCashAmount = true;
                            _selectedPreset = '2000';
                            _amountController.text = '2000';
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      _buildPresetPill(
                        presetId: '3000',
                        label: '₱3,000',
                        isEnabled: acceptsCash,
                        onTap: () {
                          controller.setTenderedAmount(3000);
                          setState(() {
                            _hasSelectedCashAmount = true;
                            _selectedPreset = '3000';
                            _amountController.text = '3000';
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      _buildPresetPill(
                        presetId: '4000',
                        label: '₱4,000',
                        isEnabled: acceptsCash,
                        onTap: () {
                          controller.setTenderedAmount(4000);
                          setState(() {
                            _hasSelectedCashAmount = true;
                            _selectedPreset = '4000';
                            _amountController.text = '4000';
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      _buildPresetPill(
                        presetId: '5000',
                        label: '₱5,000',
                        isEnabled: acceptsCash,
                        onTap: () {
                          controller.setTenderedAmount(5000);
                          setState(() {
                            _hasSelectedCashAmount = true;
                            _selectedPreset = '5000';
                            _amountController.text = '5000';
                          });
                        },
                      ),
                    ],
                  ),
                ),
                if (!keyboardOpen) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Payment Method',
                    style: TextStyle(
                      fontSize: widget.isFullWidth ? 13 : 10,
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                ],
                Row(
                  children: [
                    _buildPaymentButton(
                      label: 'Cash',
                      isSelected: controller.paymentMethod == 'cash',
                      isCompact: keyboardOpen,
                      isEnabled: !promoApplied,
                      onTap: () {
                        controller.setPaymentMethod('cash');
                        setState(() {
                          _hasSelectedCashAmount = false;
                          _selectedPreset = null;
                          _amountController.text = controller.tenderedAmount > 0
                              ? controller.tenderedAmount.toInt().toString()
                              : '0';
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildPaymentButton(
                      label: 'GCash',
                      isSelected: controller.paymentMethod == 'gcash',
                      isCompact: keyboardOpen,
                      isEnabled: true,
                      onTap: () {
                        _amountFocusNode.unfocus();
                        controller.setPaymentMethod('gcash');
                        setState(() {
                          _selectedPreset = null;
                          _amountController.text =
                              controller.total.toInt().toString();
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildPaymentButton(
                      label: 'Maya',
                      isSelected: controller.paymentMethod == 'maya',
                      isCompact: keyboardOpen,
                      isEnabled: !promoApplied,
                      onTap: () {
                        _amountFocusNode.unfocus();
                        controller.setPaymentMethod('maya');
                        setState(() {
                          _selectedPreset = null;
                          _amountController.text =
                              controller.total.toInt().toString();
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    _buildPaymentButton(
                      label: 'Split',
                      isSelected: isSplitPayment,
                      isCompact: keyboardOpen,
                      isEnabled: !promoApplied,
                      onTap: () {
                        _amountFocusNode.unfocus();
                        controller.setPaymentMethod('split');
                        final cashPart = (controller.total / 2).ceilToDouble();
                        controller.setTenderedAmount(cashPart);
                        setState(() {
                          _hasSelectedCashAmount = true;
                          _selectedPreset = null;
                          _amountController.text = cashPart.toInt().toString();
                        });
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _SplitPaymentScreen(
                              controller: controller,
                              initialDigitalMethod: _splitDigitalMethod,
                              onDigitalMethodChanged: (method) =>
                                  _splitDigitalMethod = method,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                if (isSplitPayment && !keyboardOpen) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Cash +', style: TextStyle(color: _ink)),
                      ),
                      const Text('Pay remainder with ',
                          style: TextStyle(color: _muted, fontSize: 12)),
                      DropdownButton<String>(
                        value: _splitDigitalMethod,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 'gcash', child: Text('GCash')),
                          DropdownMenuItem(value: 'maya', child: Text('Maya')),
                        ],
                        onChanged: (value) => setState(() {
                          if (value != null) _splitDigitalMethod = value;
                        }),
                      ),
                    ],
                  ),
                  Text(
                    'Cash ₱${currency.format(controller.tenderedAmount)}  ·  '
                    '$_splitDigitalMethod ₱${currency.format((controller.total - controller.tenderedAmount).clamp(0, controller.total))}',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
                SizedBox(height: keyboardOpen ? 2 : 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total',
                      style: TextStyle(
                          fontSize: widget.isFullWidth ? 19 : 13,
                          fontWeight: FontWeight.bold,
                          color: _ink),
                    ),
                    Text(
                      '₱${currency.format(controller.total)}',
                      style: TextStyle(
                          fontSize: widget.isFullWidth ? 19 : 14,
                          fontWeight: FontWeight.bold,
                          color: _ink),
                    ),
                  ],
                ),
                if (!keyboardOpen) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Change',
                          style: TextStyle(
                              fontSize: widget.isFullWidth ? 15 : 11,
                              color: _muted)),
                      Text('₱${currency.format(controller.change)}',
                          style: TextStyle(
                              fontSize: widget.isFullWidth ? 15 : 11,
                              fontWeight: FontWeight.w600,
                              color: _muted)),
                    ],
                  ),
                  const SizedBox(height: 5),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: controller.cart.isEmpty ||
                            controller.isProcessing ||
                            controller.isVoidRequestPending ||
                            ((controller.paymentMethod == 'cash' || isSplitPayment) &&
                                !_hasSelectedCashAmount)
                        ? null
                        : () {
                            if (isSplitPayment) {
                              final cashPart = controller.tenderedAmount
                                  .clamp(0, controller.total);
                              final digitalPart = controller.total - cashPart;
                              controller.setPaymentMethod(
                                'split:cash=${cashPart.toStringAsFixed(0)},'
                                '$_splitDigitalMethod=${digitalPart.toStringAsFixed(0)}',
                              );
                            }
                            widget.onProceedOrder();
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: _navy,
                      side: const BorderSide(color: _navy, width: 1.2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              widget.isFullWidth ? 16 : 10)),
                      minimumSize: Size(0,
                          keyboardOpen ? 34 : (widget.isFullWidth ? 44 : 38)),
                      padding:
                          EdgeInsets.symmetric(vertical: keyboardOpen ? 2 : 8),
                      disabledForegroundColor: Colors.white70,
                      disabledBackgroundColor: const Color(0xFF8995A9),
                    ),
                    child: controller.isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Proceed Order',
                                  style: TextStyle(
                                    fontSize: widget.isFullWidth ? 14 : 11,
                                    fontWeight: FontWeight.w700,
                                  )),
                              const SizedBox(width: 12),
                              const Icon(Icons.arrow_forward_rounded, size: 18),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quantityButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: const Color(0xFFF3F4F6),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: widget.isFullWidth ? 28 : 36,
            height: widget.isFullWidth ? 32 : 36,
            child: Icon(icon, size: widget.isFullWidth ? 16 : 20, color: _ink),
          ),
        ),
      ),
    );
  }

  Future<void> _openAmountKeypad() async {
    final controller = widget.controller;
    if (controller.paymentMethod != 'cash' &&
        !controller.paymentMethod.startsWith('split')) return;

    var amount = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 380),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          void updateAmount(String nextAmount) {
            setSheetState(() => amount = nextAmount);
            _amountController.value = TextEditingValue(
              text: amount,
              selection: TextSelection.collapsed(offset: amount.length),
            );
            controller.setTenderedAmount(
              double.tryParse(amount) ?? 0,
              notify: false,
            );
            if (mounted) {
              setState(() {
                _hasSelectedCashAmount = amount.isNotEmpty;
                _selectedPreset = null;
              });
            }
          }

          Widget digitKey(String digit) => SizedBox(
                height: 42,
                child: OutlinedButton(
                  onPressed: () => updateAmount('$amount$digit'),
                  child: Text(
                    digit,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Amount: ${amount.isEmpty ? '0' : amount}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GridView(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        mainAxisExtent: 42,
                      ),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        for (var digit = 1; digit <= 9; digit++)
                          digitKey('$digit'),
                        OutlinedButton(
                          onPressed: () => updateAmount(''),
                          child: const Text('Clear'),
                        ),
                        digitKey('0'),
                        OutlinedButton(
                          onPressed: amount.isEmpty
                              ? null
                              : () => updateAmount(
                                    amount.substring(0, amount.length - 1),
                                  ),
                          child: const Icon(Icons.backspace_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 38,
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPaymentButton({
    required String label,
    required bool isSelected,
    required bool isCompact,
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    final icon = label == 'Cash'
        ? Icons.payments_outlined
        : Icons.account_balance_wallet_outlined;
    return Expanded(
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: isCompact ? 2 : (widget.isFullWidth ? 12 : 5),
          ),
          decoration: BoxDecoration(
            color: isSelected ? _navy : Colors.white,
            borderRadius: BorderRadius.circular(widget.isFullWidth ? 14 : 10),
            border: Border.all(
              color: isSelected ? _navy : const Color(0xFFD4DEEC),
              width: 1,
            ),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: widget.isFullWidth ? 19 : 15,
                  color: isSelected
                      ? Colors.white
                      : (isEnabled ? _muted : const Color(0xFFD1D5DB)),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: widget.isFullWidth ? 14 : 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? Colors.white
                        : (isEnabled ? _ink : const Color(0xFF9CA3AF)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServiceModeButton(String mode, String label) {
    final isSelected = widget.controller.serviceMode == mode;
    return SizedBox(
      height: widget.isFullWidth ? 56 : 48,
      child: isSelected
          ? FilledButton(
              onPressed: () => widget.controller.setServiceMode(mode),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: () => widget.controller.setServiceMode(mode),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF374151),
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                side: const BorderSide(color: Color(0xFFD1D5DB)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(label),
            ),
    );
  }

  Widget _buildPresetPill({
    required String presetId,
    required String label,
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    final isSelected = isEnabled && _selectedPreset == presetId;
    return InkWell(
      onTap: isEnabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.isFullWidth ? 14 : 9,
          vertical: widget.isFullWidth ? 10 : 3,
        ),
        decoration: BoxDecoration(
          color: !isEnabled
              ? const Color(0xFFF3F4F6)
              : isSelected
                  ? _navy
                  : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: !isEnabled
                ? const Color(0xFFE5E7EB)
                : isSelected
                    ? const Color(0xFF5687FF)
                    : const Color(0xFFD4DEEC),
            width: isSelected && widget.isFullWidth ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: widget.isFullWidth ? 13 : 9,
              fontWeight: FontWeight.w600,
              color: !isEnabled
                  ? const Color(0xFF9CA3AF)
                  : isSelected
                      ? Colors.white
                      : const Color(0xFF374151),
            ),
          ),
        ),
      ),
    );
  }
}
