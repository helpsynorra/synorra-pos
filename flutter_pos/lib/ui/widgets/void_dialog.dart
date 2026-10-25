import 'package:flutter/material.dart';
import '../../models/order_item.dart';

class VoidDialog extends StatefulWidget {
  final List<OrderItem> cart;
  final bool isManager;
  final bool isRequestPending;
  final bool isOnline;
  final Future<Map<String, dynamic>> Function(
    String reason,
    String managerUsername,
    String managerPassword,
  ) onConfirmVoid;
  final Future<Map<String, dynamic>> Function(String reason) onRequestVoid;

  const VoidDialog({
    super.key,
    required this.cart,
    required this.isManager,
    required this.isRequestPending,
    required this.isOnline,
    required this.onConfirmVoid,
    required this.onRequestVoid,
  });

  @override
  State<VoidDialog> createState() => _VoidDialogState();
}

class _VoidDialogState extends State<VoidDialog> {
  final TextEditingController _reasonController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void dispose() {
    _reasonController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _confirmVoid() async {
    final reason = _reasonController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (widget.cart.isEmpty) {
      setState(() => _errorMessage = 'Select a ticket to void.');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _errorMessage = 'Enter a reason for voiding.');
      return;
    }
    if (!widget.isManager && (username.isEmpty || password.isEmpty)) {
      setState(() => _errorMessage = 'Manager credentials required to void.');
      return;
    }

    final navigator = Navigator.of(context);
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    try {
      final result = await widget.onConfirmVoid(reason, username, password);
      if (!mounted) return;
      if (result['ok'] == true) {
        navigator.pop();
      } else {
        setState(() {
          _errorMessage = result['error']?.toString() ?? 'Unable to void.';
          _isProcessing = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _isProcessing = false;
      });
    }
  }

  Future<void> _requestVoid() async {
    final reason = _reasonController.text.trim();
    if (!widget.isOnline) {
      setState(() => _errorMessage = 'Request unavailable offline.');
      return;
    }
    if (widget.cart.isEmpty) {
      setState(() => _errorMessage = 'Select a ticket to void.');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _errorMessage = 'Enter a reason for voiding.');
      return;
    }

    final navigator = Navigator.of(context);
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    try {
      final result = await widget.onRequestVoid(reason);
      if (!mounted) return;
      if (result['ok'] == true) {
        navigator.pop();
      } else {
        setState(() {
          _errorMessage =
              result['error']?.toString() ?? 'Unable to send request.';
          _isProcessing = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _isProcessing = false;
      });
    }
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
        ),
      );

  Widget _labeledField({
    required String label,
    required String hint,
    required TextEditingController controller,
    bool obscureText = false,
    TextInputAction textInputAction = TextInputAction.next,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF404040),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          textInputAction: textInputAction,
          style: const TextStyle(fontSize: 14),
          decoration: _decoration(hint),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final compact = screenSize.width < 420;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 24,
        vertical: 16,
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: screenSize.height * 0.86,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(compact ? 18 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.error_outline,
                          size: 25, color: Color(0xFF292929)),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton(
                        tooltip: 'Close',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                            width: 32, height: 32),
                        padding: EdgeInsets.zero,
                        onPressed:
                            _isProcessing ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close,
                            size: 20, color: Color(0xFF777777)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Void checkout',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF171717),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.isManager
                    ? 'This action cannot be undone.'
                    : 'Manager approval required to void.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF737373)),
              ),
              const SizedBox(height: 22),
              if (!widget.isManager) ...[
                _labeledField(
                  label: 'Manager username',
                  hint: 'Enter username',
                  controller: _usernameController,
                ),
                const SizedBox(height: 14),
                _labeledField(
                  label: 'Manager password',
                  hint: 'Enter password',
                  controller: _passwordController,
                  obscureText: true,
                ),
                const SizedBox(height: 18),
              ],
              const Text(
                'Reason for Voiding *',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF404040),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _reasonController,
                minLines: 2,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(fontSize: 14),
                decoration: _decoration(
                  'e.g., internal changed mind, wrong order input...',
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style:
                      const TextStyle(color: Color(0xFFDC2626), fontSize: 12),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isProcessing ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF525252),
                        side: const BorderSide(color: Color(0xFFE5E5E5)),
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isProcessing || widget.isRequestPending
                          ? null
                          : _confirmVoid,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFF737373),
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Confirm Void'),
                    ),
                  ),
                ],
              ),
              if (!widget.isManager) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isProcessing ||
                            widget.isRequestPending ||
                            !widget.isOnline
                        ? null
                        : _requestVoid,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: Colors.black),
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    child: Text(
                      widget.isRequestPending
                          ? 'Waiting for Admin approval'
                          : widget.isOnline
                              ? 'Request to admin'
                              : 'Unavailable offline',
                      maxLines: 1,
                      softWrap: false,
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
