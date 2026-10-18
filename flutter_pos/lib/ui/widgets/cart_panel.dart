import 'package:flutter/material.dart';
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

class _CartPanelState extends State<CartPanel> {
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();
  bool _hasSelectedCashAmount = false;
  String? _selectedPreset;

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

    final amountText = widget.controller.paymentMethod != 'cash'
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

    return Container(
      width: widget.isFullWidth ? double.infinity : widget.panelWidth,
      decoration: BoxDecoration(
        color: Colors.white,
        border: widget.isFullWidth
            ? null
            : const Border(
                left: BorderSide(color: Color(0xFFE5E7EB), width: 1),
              ),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: keyboardOpen ? 2 : 8,
              bottom: keyboardOpen ? 1 : 4,
            ),
            child: Text(
              'Checkout',
              style: TextStyle(
                fontSize: keyboardOpen ? 14 : 17,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF111827),
                letterSpacing: -0.4,
              ),
            ),
          ),
          if (!keyboardOpen)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      'NAME',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9CA3AF),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'QTY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9CA3AF),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'PRICE',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9CA3AF),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: controller.cart.isEmpty
                ? const Center(
                    child: Text(
                      'No items yet.',
                      style: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 11,
                      ),
                    ),
                  )
                : ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      scrollbars: false,
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      itemCount: controller.cart.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
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
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  if (controller.cart[index].optionsSummary
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      controller.cart[index].optionsSummary,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 5,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _quantityButton(
                                    icon: Icons.remove,
                                    label: 'Decrease ${controller.cart[index].name} quantity',
                                    onTap: () => controller.updateCartQty(
                                      index,
                                      controller.cart[index].qty - 1,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 24,
                                    child: Text(
                                      '${controller.cart[index].qty}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  _quantityButton(
                                    icon: Icons.add,
                                    label: 'Increase ${controller.cart[index].name} quantity',
                                    onTap: () => widget.controller.updateCartQty(
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                  color: Color(0xFF111827),
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
              horizontal: 12,
              vertical: keyboardOpen ? 3 : 7,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
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
                          child: _buildServiceModeButton('take-out', 'Take Out'),
                        ),
                    ],
                  ),
                SizedBox(height: keyboardOpen ? 2 : 5),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Amount',
                        style: TextStyle(
                            fontSize: 12, color: Color(0xFF374151)),
                      ),
                    ),
                    SizedBox(
                      width: 92,
                      height: keyboardOpen ? 24 : 28,
                      child: TextField(
                        enabled: isCashPayment,
                        readOnly: true,
                        showCursor: false,
                        onTap: isCashPayment ? _openAmountKeypad : null,
                        controller: _amountController,
                        focusNode: _amountFocusNode,
                        keyboardType: TextInputType.none,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFFD1D5DB)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFFD1D5DB)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Colors.black, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: keyboardOpen ? 1 : 4),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildPresetPill(
                        presetId: 'exact',
                        label: 'Exact',
                        isEnabled: isCashPayment,
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
                        isEnabled: isCashPayment,
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
                        isEnabled: isCashPayment,
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
                        isEnabled: isCashPayment,
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
                        isEnabled: isCashPayment,
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
                        isEnabled: isCashPayment,
                        onTap: () {
                          controller.setTenderedAmount(4000);
                          setState(() {
                            _hasSelectedCashAmount = true;
                            _selectedPreset = '4000';
                            _amountController.text = '4000';
                          });
                        },
                      ),
                    ],
                  ),
                ),
                if (!keyboardOpen) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Pay with',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF6B7280),
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
                  ],
                ),
                SizedBox(height: keyboardOpen ? 2 : 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                    ),
                    Text(
                      '₱${currency.format(controller.total)}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                    ),
                  ],
                ),
                if (!keyboardOpen) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Change',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF4B5563))),
                      Text('₱${currency.format(controller.change)}',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
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
                            (controller.paymentMethod == 'cash' &&
                                !_hasSelectedCashAmount)
                        ? null
                        : widget.onProceedOrder,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Colors.black, width: 1.2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      minimumSize: Size(0, keyboardOpen ? 28 : 36),
                      padding:
                          EdgeInsets.symmetric(vertical: keyboardOpen ? 2 : 6),
                      disabledForegroundColor: const Color(0xFF9CA3AF),
                    ),
                    child: controller.isProcessing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black),
                          )
                        : const Text(
                            'Proceed Order',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600),
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
            width: 44,
            height: 44,
            child: Icon(icon, size: 20, color: const Color(0xFF111827)),
          ),
        ),
      ),
    );
  }

  Future<void> _openAmountKeypad() async {
    final controller = widget.controller;
    if (controller.paymentMethod != 'cash') return;

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
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: isCompact ? 2 : 5),
          decoration: BoxDecoration(
            color: isSelected ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? Colors.black : const Color(0xFFD1D5DB),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF111827),
              ),
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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: !isEnabled
              ? const Color(0xFFF3F4F6)
              : isSelected
                  ? Colors.black
                  : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: !isEnabled
                ? const Color(0xFFE5E7EB)
                : isSelected
                    ? Colors.black
                    : const Color(0xFFD1D5DB),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
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
