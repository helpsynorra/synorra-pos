import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../manila_time.dart';
import '../../models/staff_user.dart';
import '../pos_status_colors.dart';
import 'offline_staff_avatar.dart';

class BaristaShiftDialog extends StatefulWidget {
  final List<StaffUser> onShiftBaristas;
  final Set<String> onBreakStaffIds;
  final Map<String, String> onShiftSince;
  final List<StaffUser> staffUsers;
  final String authMode;
  final Future<StaffUser?> Function(String username, String password)
      authenticateBarista;
  final Future<String?> Function(String staffUserId) resolveStaffAvatarUrl;
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
    this.onBreakStaffIds = const <String>{},
    this.onShiftSince = const <String, String>{},
    required this.staffUsers,
    required this.authMode,
    required this.authenticateBarista,
    required this.resolveStaffAvatarUrl,
    required this.onPunch,
  });

  @override
  State<BaristaShiftDialog> createState() => _BaristaShiftDialogState();
}

class _BaristaShiftDialogState extends State<BaristaShiftDialog> {
  static const Color _navy = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _canvas = Color(0xFFF8FAFC);

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  StaffUser? _target;
  String? _action; // login | logout | break_start | break_end
  String? _selectedStaffId;
  Uint8List? _attendancePhoto;
  String? _selectedRole;
  String? _error;
  bool _isLoading = false;
  bool get _requiresPhoto => widget.authMode != 'username_password';
  bool get _selectByName => widget.authMode == 'photo_full_name_pin';

  bool _isOnBreak(StaffUser staff) => widget.onBreakStaffIds.contains(staff.id);

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
        setState(() {
          _attendancePhoto = bytes;
          _error = null;
        });
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

  Future<void> _handlePunch() async {
    if (_isLoading) return;
    final action = _action;
    if (action == null) return;
    final target = _target;

    if (action == 'login') {
      if (_selectedRole == null) {
        setState(() => _error = 'Choose the staff role to continue.');
        return;
      }
      if (_selectByName && _selectedStaffId == null) {
        setState(() => _error = 'Select your full name and enter your PIN.');
        return;
      }
      if (!_selectByName && _usernameController.text.trim().isEmpty) {
        setState(() => _error = 'Please enter both username and password.');
        return;
      }
    }
    if (_passwordController.text.isEmpty) {
      setState(() => _error = _selectByName
          ? 'Enter your PIN / password.'
          : 'Please enter your password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      if (!await _captureAttendancePhoto()) return;
      final staff = await _authenticateBarista();
      if (staff == null) {
        if (mounted) {
          setState(() =>
              _error = 'Those details do not match an active staff account.');
        }
        return;
      }
      if (action == 'login') {
        if (staff.role != _selectedRole ||
            (_selectByName && staff.id != _selectedStaffId)) {
          if (mounted) {
            setState(() =>
                _error = 'Those details do not match the selected staff role.');
          }
          return;
        }
      } else if (target == null || staff.id != target.id) {
        if (mounted) {
          setState(() => _error =
              'Only ${target?.name ?? 'the staff member'} can ${_actionVerb(action)} with their own credentials.');
        }
        return;
      }

      await widget.onPunch(
        staff,
        action,
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

  String _actionVerb(String action) {
    switch (action) {
      case 'break_start':
        return 'start a break';
      case 'break_end':
        return 'resume their shift';
      case 'logout':
        return 'clock out';
      default:
        return 'clock in';
    }
  }

  void _selectAction(String action) {
    if (_isLoading) return;
    setState(() {
      _error = null;
      _attendancePhoto = null;
      if (action == 'login') {
        _action = action;
        _target = null;
        _selectedRole = null;
        _selectedStaffId = null;
        _usernameController.clear();
        _passwordController.clear();
        return;
      }
      final target = _target;
      if (target == null) return;
      _action = action;
      _selectedRole = target.role;
      _selectedStaffId = target.id;
      _usernameController.text = target.username;
      _passwordController.clear();
    });
  }

  void _selectTarget(StaffUser staff) {
    if (_isLoading) return;
    setState(() {
      if (_target?.id == staff.id) {
        _target = null;
        _action = null;
      } else {
        _target = staff;
        _action = null;
        _selectedRole = staff.role;
        _selectedStaffId = staff.id;
        _usernameController.text = staff.username;
        _passwordController.clear();
      }
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
      _error = null;
    });
  }

  String _sinceLabel(String? at) {
    final parsed = at == null ? null : ManilaTime.parse(at);
    if (parsed == null) return '—';
    return DateFormat('h:mm a').format(parsed);
  }

  String get _formTitle {
    switch (_action) {
      case 'break_start':
        return 'Start break';
      case 'break_end':
        return 'Resume shift';
      case 'logout':
        return 'Clock out';
      default:
        return 'Clock in';
    }
  }

  String get _primaryLabel {
    switch (_action) {
      case 'break_start':
        return 'Start break';
      case 'break_end':
        return 'Resume shift';
      case 'logout':
        return 'Clock out';
      default:
        return 'Clock in';
    }
  }

  IconData get _primaryIcon {
    switch (_action) {
      case 'break_start':
        return Icons.free_breakfast_outlined;
      case 'break_end':
        return Icons.play_circle_outline;
      case 'logout':
        return Icons.logout;
      default:
        return Icons.login;
    }
  }

  String get _calloutText {
    if (_requiresPhoto) {
      return 'The photo is captured only for store timekeeping. Synorra POS does not use facial recognition.';
    }
    if (_action == 'break_start') {
      return 'Break time keeps the shift open. The staff member stays clocked in and can resume right after.';
    }
    if (_action == 'break_end') {
      return 'Resuming continues the same shift, so break time is not counted as a clock-out.';
    }
    return 'The staff member will be clocked in and the shift will start. Make sure to enter the correct credentials.';
  }

  PosStatusTone get _actionTone => PosStatusColors.forAttendanceAction(_action);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 18),
              _buildOnShiftSection(),
              const SizedBox(height: 18),
              _buildActions(),
              if (_action != null) ...[
                const SizedBox(height: 16),
                _buildForm(),
              ],
              const SizedBox(height: 14),
              _buildCallout(),
              if (_error != null) ...[
                const SizedBox(height: 10),
                _buildError(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Attendance',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: _navy,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Clock in, take a break, or end a shift.',
                style: TextStyle(fontSize: 12.5, color: _muted),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: _canvas,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, size: 18, color: _muted),
          ),
        ),
      ],
    );
  }

  Widget _buildOnShiftSection() {
    final onShift = widget.onShiftBaristas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'ON SHIFT',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: _muted,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: PosStatusColors.active.tint,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${onShift.length} active',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: PosStatusColors.active.ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        if (onShift.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: _canvas,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: const Row(
              children: [
                Icon(Icons.person_off_outlined, size: 20, color: _muted),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No one is clocked in yet. Clock in a staff member below.',
                    style: TextStyle(fontSize: 12, height: 1.35, color: _muted),
                  ),
                ),
              ],
            ),
          )
        else
          ...onShift.map(_buildStaffCard),
      ],
    );
  }

  Widget _buildStaffCard(StaffUser staff) {
    final onBreak = _isOnBreak(staff);
    final tone = onBreak ? PosStatusColors.waiting : PosStatusColors.active;
    final selected = _target?.id == staff.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFFF8FAFC) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: _isLoading ? null : () => _selectTarget(staff),
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: selected ? _navy : _border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                OfflineStaffAvatar(
                  staff: staff,
                  resolveSignedUrl: widget.resolveStaffAvatarUrl,
                  radius: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        staff.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${staff.title} · Since ${_sinceLabel(widget.onShiftSince[staff.id])}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: _muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: tone.tint,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: tone.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: tone.solid,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        onBreak ? 'On break' : 'On shift',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: tone.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActions() {
    final target = _target;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'CLOCK IN',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: _muted,
              ),
            ),
            const Spacer(),
            if (target != null)
              Text(
                'Tap a card to switch staff',
                style: TextStyle(
                    fontSize: 10.5, color: _muted.withValues(alpha: 0.9)),
              ),
          ],
        ),
        const SizedBox(height: 9),
        _buildActionTile(
          action: 'login',
          label: 'Clock In',
          caption: 'Start a new shift',
          icon: Icons.login,
        ),
        if (target != null) ...[
          const SizedBox(height: 16),
          Text(
            'MANAGE ${target.name.toUpperCase()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: _muted,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _buildActionTile(
                  action: _isOnBreak(target) ? 'break_end' : 'break_start',
                  label: _isOnBreak(target) ? 'Resume Shift' : 'Break Time',
                  icon: _isOnBreak(target)
                      ? Icons.play_circle_outline
                      : Icons.free_breakfast_outlined,
                  vertical: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionTile(
                  action: 'logout',
                  label: 'Clock Out',
                  icon: Icons.logout,
                  vertical: true,
                ),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 8),
          const Text(
            'Tap a staff card above to take a break or clock out.',
            style: TextStyle(fontSize: 11.5, color: _muted),
          ),
        ],
      ],
    );
  }

  Widget _buildActionTile({
    required String action,
    required String label,
    required IconData icon,
    String? caption,
    bool vertical = false,
  }) {
    final tone = PosStatusColors.forAttendanceAction(action);
    final selected = _action == action;
    final content = vertical
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _tileIcon(icon),
              const Spacer(),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          )
        : Row(
            children: [
              _tileIcon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (caption != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, size: 18, color: Colors.white),
            ],
          );

    return Material(
      color: tone.solid,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: _isLoading ? null : () => _selectAction(action),
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: vertical ? 76 : 62,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected ? _navy : Colors.transparent,
              width: 2,
            ),
          ),
          child: content,
        ),
      ),
    );
  }

  Widget _tileIcon(IconData icon) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, size: 17, color: Colors.white),
    );
  }

  Widget _buildForm() {
    final tone = _actionTone;
    final target = _target;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tone.tint,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(_primaryIcon, size: 15, color: tone.ink),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  target == null ? _formTitle : '$_formTitle · ${target.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _navy,
                  ),
                ),
              ),
              Text(
                target == null ? 'New shift' : 'Verify identity',
                style: const TextStyle(fontSize: 10.5, color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_action == 'login') ...[
            Row(
              children: [
                Expanded(
                  child: _roleChip('Cashier', 'pos_cashier'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _roleChip('Barista', 'barista'),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (_selectByName && _action == 'login') ...[
            const _FieldLabel('Full name'),
            const SizedBox(height: 5),
            DropdownButtonFormField<String>(
              initialValue: _selectedStaffId,
              isExpanded: true,
              decoration: _fieldDecoration(null),
              hint: const Text('Select your name'),
              items: widget.staffUsers
                  .where((staff) =>
                      staff.role == _selectedRole && staff.canClockShift)
                  .map((staff) => DropdownMenuItem(
                        value: staff.id,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OfflineStaffAvatar(
                              staff: staff,
                              resolveSignedUrl: widget.resolveStaffAvatarUrl,
                              radius: 12,
                            ),
                            const SizedBox(width: 8),
                            Flexible(child: Text(staff.name)),
                          ],
                        ),
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
            const SizedBox(height: 10),
          ] else if (_selectByName && target != null) ...[
            Text(
              'Selected staff: ${target.name}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _navy,
              ),
            ),
            const SizedBox(height: 10),
          ] else ...[
            const _FieldLabel('Username'),
            const SizedBox(height: 5),
            TextField(
              controller: _usernameController,
              readOnly: target != null,
              textInputAction: TextInputAction.next,
              style: TextStyle(
                fontSize: 13,
                color: target != null ? _muted : _navy,
              ),
              decoration: _fieldDecoration('Enter your username'),
            ),
            const SizedBox(height: 10),
          ],
          _FieldLabel(_selectByName ? 'PIN / Password' : 'Password'),
          const SizedBox(height: 5),
          TextField(
            controller: _passwordController,
            obscureText: true,
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.visiblePassword,
            style: const TextStyle(fontSize: 13, color: _navy),
            decoration: _fieldDecoration(
              _selectByName
                  ? 'Enter your staff PIN / password'
                  : 'Enter your password',
            ),
            onSubmitted: (_) => _handlePunch(),
          ),
          if (_requiresPhoto) ...[
            const SizedBox(height: 12),
            _buildPhotoCapture(),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handlePunch,
              style: ElevatedButton.styleFrom(
                backgroundColor: tone.solid,
                foregroundColor: Colors.white,
                disabledBackgroundColor: tone.solid.withValues(alpha: 0.5),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
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
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_primaryIcon, size: 17),
                        const SizedBox(width: 8),
                        Text(
                          _primaryLabel,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleChip(String label, String role) {
    final selected = _selectedRole == role;
    return Material(
      color: selected ? _navy : Colors.white,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: _isLoading ? null : () => _selectStaffRole(role),
        borderRadius: BorderRadius.circular(11),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: selected ? _navy : _border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : _muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoCapture() {
    final tone = _actionTone;
    final captured = _attendancePhoto != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [tone.solid, tone.ink],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: InkWell(
              onTap: _isLoading
                  ? null
                  : () async {
                      setState(() {
                        _error = null;
                        _attendancePhoto = null;
                      });
                      await _captureAttendancePhoto();
                    },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.photo_camera_outlined,
                        size: 18, color: Colors.white),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        captured
                            ? 'Retake attendance photo'
                            : 'Capture live attendance photo',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Icon(
                      captured
                          ? Icons.check_circle
                          : Icons.arrow_forward_ios_rounded,
                      size: captured ? 18 : 12,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (captured) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  _attendancePhoto!,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Attendance photo ready',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCallout() {
    final tone = _requiresPhoto ? PosStatusColors.info : _actionTone;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _requiresPhoto ? Icons.lock_outline : Icons.info_outline,
            size: 15,
            color: tone.ink,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _calloutText,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: tone.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: PosStatusColors.danger.tint,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: PosStatusColors.danger.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline,
              size: 15, color: PosStatusColors.danger.ink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: PosStatusColors.danger.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: _navy, width: 1.4),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: Color(0xFF475569),
      ),
    );
  }
}
