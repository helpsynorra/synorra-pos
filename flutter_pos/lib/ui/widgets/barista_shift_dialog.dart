import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/staff_user.dart';

class BaristaShiftDialog extends StatefulWidget {
  final List<StaffUser> onShiftBaristas;
  final List<StaffUser> staffUsers;
  final String authMode;
  final Future<StaffUser?> Function(String username, String password)
      authenticateBarista;
  final Future<void> Function(
    StaffUser staff,
    String type, {
    required String username,
    required String password,
    Uint8List? photoBytes,
  }) onPunch;

  const BaristaShiftDialog({
    super.key,
    required this.onShiftBaristas,
    required this.staffUsers,
    required this.authMode,
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
  String? _selectedStaffId;
  Uint8List? _attendancePhoto;
  String? _selectedRole;
  String? _error;
  bool _isLoading = false;
  bool get _requiresPhoto => widget.authMode != 'username_password';
  bool get _selectByName => widget.authMode == 'photo_full_name_pin';

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

  Future<bool> _captureAttendancePhoto() async {
    if (!_requiresPhoto) return true;
    if (_attendancePhoto != null) return true;
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 65,
        maxWidth: 960,
      );
      if (photo == null) {
        if (mounted) {
          setState(() => _error = 'A live attendance photo is required.');
        }
        return false;
      }
      final bytes = await photo.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) {
          setState(
            () =>
                _error = 'The camera did not return a photo. Please try again.',
          );
        }
        return false;
      }
      if (mounted) {
        setState(() => _attendancePhoto = bytes);
      }
      return true;
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error =
            'Could not open the camera: ${error.message ?? error.code}');
      }
      return false;
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(() =>
            _error = 'Could not read the attendance photo: ${error.message}');
      }
      return false;
    }
  }

  Future<void> _handleClockIn() async {
    if (_isLoading) return;
    if (_selectedRole == null) return;
    if ((_selectByName
            ? _selectedStaffId == null
            : _usernameController.text.trim().isEmpty) ||
        _passwordController.text.isEmpty) {
      setState(() => _error = _selectByName
          ? 'Select your full name and enter your PIN.'
          : 'Please enter both username and password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (!await _captureAttendancePhoto()) return;
      final staff = await _authenticateBarista();
      if (staff == null ||
          staff.role != _selectedRole ||
          (_selectByName && staff.id != _selectedStaffId)) {
        if (mounted) {
          setState(() =>
              _error = 'Those details do not match the selected staff role.');
        }
        return;
      }

      await widget.onPunch(
        staff,
        'login',
        username: staff.username,
        password: _passwordController.text,
        photoBytes: _attendancePhoto,
      );
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
      _selectedStaffId = barista.id;
      _attendancePhoto = null;
      _error = null;
    });
  }

  void _selectStaffRole(String role) {
    setState(() {
      _selectedRole = role;
      _usernameController.clear();
      _passwordController.clear();
      _selectedStaffId = null;
      _attendancePhoto = null;
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
      if (!await _captureAttendancePhoto()) return;
      final staff = await _authenticateBarista();
      if (staff == null || staff.id != onShift.id) {
        if (mounted) {
          setState(() => _error =
              'Only the staff member on shift can clock out with their credentials.');
        }
        return;
      }

      await widget.onPunch(
        staff,
        'logout',
        username: staff.username,
        password: _passwordController.text,
        photoBytes: _attendancePhoto,
      );
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
                              child: Text(
                                  '${barista.name} · ${barista.title} is on shift',
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
                if (_selectByName && _clockOutTarget == null) ...[
                  const Text('Full name',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedStaffId,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    hint: const Text('Select your name'),
                    items: widget.staffUsers
                        .where((staff) =>
                            staff.role == _selectedRole && staff.canClockShift)
                        .map((staff) => DropdownMenuItem(
                              value: staff.id,
                              child: Text(staff.name),
                            ))
                        .toList(),
                    onChanged: _isLoading
                        ? null
                        : (staffId) {
                            final staff = widget.staffUsers
                                .where((entry) => entry.id == staffId)
                                .firstOrNull;
                            setState(() {
                              _selectedStaffId = staffId;
                              _usernameController.text = staff?.username ?? '';
                              _attendancePhoto = null;
                              _error = null;
                            });
                          },
                  ),
                ] else if (_selectByName) ...[
                  Text(
                    'Selected staff: ${_clockOutTarget!.name}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ] else ...[
                  const Text('Username',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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
                ],
                const SizedBox(height: 14),
                Text(_selectByName ? 'PIN / Password' : 'Password',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.visiblePassword,
                  decoration: InputDecoration(
                    hintText: _selectByName
                        ? 'Enter your staff password / PIN'
                        : null,
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
                if (_requiresPhoto) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F6FB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Live photo proof is captured solely for store timekeeping. Synorra POS does not use facial recognition technology.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: Color(0xFF53627F),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            setState(() {
                              _error = null;
                              _attendancePhoto = null;
                            });
                            await _captureAttendancePhoto();
                          },
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(_attendancePhoto == null
                        ? 'Capture live attendance photo'
                        : 'Retake attendance photo'),
                  ),
                  if (_attendancePhoto != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _attendancePhoto!,
                        height: 120,
                        width: 160,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                ],
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
          backgroundColor:
              selected ? const Color(0xFF101D37) : const Color(0xFF172843),
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
