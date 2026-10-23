import 'package:flutter/material.dart';
import '../../models/staff_user.dart';

class BaristaShiftDialog extends StatefulWidget {
  final List<StaffUser> onShiftBaristas;
  final Future<StaffUser?> Function(String username, String password)
      authenticateBarista;
  final Future<void> Function(StaffUser staff, String type) onPunch;

  const BaristaShiftDialog({
    super.key,
    required this.onShiftBaristas,
    required this.authenticateBarista,
    required this.onPunch,
  });

  @override
  State<BaristaShiftDialog> createState() => _BaristaShiftDialogState();
}

class _BaristaShiftDialogState extends State<BaristaShiftDialog> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  StaffUser? _clockOutTarget;
  String? _selectedRole;
  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<StaffUser?> _authenticateBarista() async {
    final staff = await widget.authenticateBarista(
      _usernameController.text.trim(),
      _passwordController.text,
    );
    return staff?.canClockShift == true ? staff : null;
  }

  Future<void> _handleClockIn() async {
    if (_isLoading) return;
    if (_selectedRole == null) return;
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() => _error = 'Please enter both username and password');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final staff = await _authenticateBarista();
      if (staff == null || staff.role != _selectedRole) {
        if (mounted) {
          setState(() => _error = 'Those details do not match the selected staff role.');
        }
        return;
      }

      await widget.onPunch(staff, 'login');
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectClockOutTarget(StaffUser barista) {
    setState(() {
      _clockOutTarget = barista;
      _selectedRole = barista.role;
      _usernameController.text = barista.username;
      _passwordController.clear();
      _error = null;
    });
  }

  void _selectStaffRole(String role) {
    setState(() {
      _selectedRole = role;
      _usernameController.clear();
      _passwordController.clear();
      _error = null;
    });
  }

  Future<void> _handleClockOut() async {
    if (_isLoading) return;
    final onShift = _clockOutTarget;
    if (onShift == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final staff = await _authenticateBarista();
      if (staff == null || staff.id != onShift.id) {
        if (mounted) {
          setState(() => _error =
              'Only the staff member on shift can clock out with their credentials.');
        }
        return;
      }

      await widget.onPunch(staff, 'logout');
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 440,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Staff on Shift / Team',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827)),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close,
                        size: 20, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (widget.onShiftBaristas.isNotEmpty)
                ...widget.onShiftBaristas.map((barista) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.circle,
                              size: 8, color: Color(0xFF16A34A)),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text('${barista.name} · ${barista.title} is on shift',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600))),
                          TextButton(
                            onPressed: () => _selectClockOutTarget(barista),
                            child: Text(_clockOutTarget?.id == barista.id
                                ? 'Selected'
                                : 'Clock out'),
                          ),
                        ],
                      ),
                    ))
              else ...[
                const Text('No staff member is on shift yet.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                const SizedBox(height: 20),
              ],
              if (_clockOutTarget == null && _selectedRole == null) ...[
                const Text('Choose your staff role to continue.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                const SizedBox(height: 18),
                _roleButton('Cashier', 'pos_cashier'),
                const SizedBox(height: 10),
                _roleButton('Barista', 'barista'),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _clockOutTarget == null ? 'STAFF LOGIN' : 'STAFF LOGOUT',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF718096)),
                    ),
                    if (_clockOutTarget == null)
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => setState(() {
                                  _selectedRole = null;
                                  _error = null;
                                  _usernameController.clear();
                                  _passwordController.clear();
                                }),
                        child: const Text('Change role'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _clockOutTarget == null
                      ? 'Sign in as ${_selectedRole == 'pos_cashier' ? 'Cashier' : 'Barista'}'
                      : 'Confirm your identity to clock out',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF24324A)),
                ),
                const SizedBox(height: 14),
                const Text('Username',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                TextField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Password',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onSubmitted: (_) async {
                    if (_clockOutTarget == null) {
                      await _handleClockIn();
                    } else {
                      await _handleClockOut();
                    }
                  },
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(
                        color: Color(0xFFDC2626), fontSize: 12)),
              ],
              if (_selectedRole != null || _clockOutTarget != null) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          if (_clockOutTarget == null) {
                            _handleClockIn();
                          } else {
                            _handleClockOut();
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF101D37),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _clockOutTarget == null ? 'Clock in' : 'Clock out'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleButton(String label, String role) {
    final selected = _selectedRole == role;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _isLoading ? null : () => _selectStaffRole(role),
        style: ElevatedButton.styleFrom(
          backgroundColor: selected
              ? const Color(0xFF101D37)
              : const Color(0xFF172843),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      ),
    );
  }
}
