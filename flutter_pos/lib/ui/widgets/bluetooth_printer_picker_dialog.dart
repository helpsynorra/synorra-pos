import 'package:flutter/material.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import '../../services/bluetooth_printer_service.dart';
import '../theme.dart';

class BluetoothPrinterPickerDialog extends StatefulWidget {
  final PrinterRole role;

  const BluetoothPrinterPickerDialog({
    super.key,
    required this.role,
  });

  @override
  State<BluetoothPrinterPickerDialog> createState() =>
      _BluetoothPrinterPickerDialogState();
}

class _BluetoothPrinterPickerDialogState
    extends State<BluetoothPrinterPickerDialog> {
  final _bluetooth = FlutterClassicBluetooth();
  final _printers = BluetoothPrinterService.instance;
  List<BtcDevice> _devices = [];
  bool _loading = true;
  bool _scanning = false;
  String? _error;
  LabelPrinterLanguage _language = LabelPrinterLanguage.tspl;

  bool get _isslip => widget.role == PrinterRole.slip;

  @override
  void initState() {
    super.initState();
    _language = _printers.labelLanguage;
    _loadPairedDevices();
  }

  Future<void> _loadPairedDevices() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final permission = await _bluetooth.requestPermissions(
        permissions: {BtcPermission.connect},
      );
      if (permission != BtcPermissionStatus.granted &&
          permission != BtcPermissionStatus.notRequired) {
        throw StateError('Allow Bluetooth access to choose a printer.');
      }
      final devices = await _bluetooth.getPairedDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final permission = await _bluetooth.requestPermissions(
        permissions: {BtcPermission.scan, BtcPermission.connect},
      );
      if (permission != BtcPermissionStatus.granted &&
          permission != BtcPermissionStatus.notRequired) {
        throw StateError('Allow Bluetooth scan access to find nearby printers.');
      }
      final found = await _bluetooth.scan(
        timeout: const Duration(seconds: 8),
      );
      final devicesByAddress = {for (final device in _devices) device.address: device};
      for (final device in found) {
        final previous = devicesByAddress[device.address];
        devicesByAddress[device.address] = previous == null
            ? device
            : previous.mergedWith(device);
      }
      if (!mounted) return;
      setState(() {
        _devices = devicesByAddress.values.toList();
        _scanning = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _scanning = false;
      });
    }
  }

  Future<void> _connect(BtcDevice device) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _printers.connect(
        widget.role,
        device,
        language: _isslip ? null : _language,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _disconnect({bool forget = false}) async {
    try {
      await _printers.disconnect(widget.role, clearSaved: forget);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isslip ? 'Connect slip' : 'Connect labels';
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      title: Row(
        children: [
          const Icon(Icons.bluetooth, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(title)),
          IconButton(
            tooltip: 'Scan nearby devices',
            onPressed: _scanning || _loading ? null : _scan,
            icon: _scanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isslip)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SegmentedButton<LabelPrinterLanguage>(
                  segments: const [
                    ButtonSegment(
                      value: LabelPrinterLanguage.tspl,
                      label: Text('TSPL'),
                    ),
                    ButtonSegment(
                      value: LabelPrinterLanguage.cpcl,
                      label: Text('CPCL'),
                    ),
                  ],
                  selected: {_language},
                  onSelectionChanged: (selection) {
                    setState(() => _language = selection.first);
                  },
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: SynorraTheme.voidRed, fontSize: 12),
                ),
              ),
            if (_loading && _devices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else if (_devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('No paired printers found. Scan for nearby printers.'),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _devices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    final connected = _printers.isConnected(widget.role) &&
                        _printers.deviceName(widget.role) == device.displayName;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.print_outlined),
                      title: Text(device.displayName),
                      subtitle: Text(device.address),
                      trailing: connected
                          ? const Icon(Icons.check_circle, color: SynorraTheme.statusOnline)
                          : const Icon(Icons.bluetooth_connected),
                      enabled: !_loading,
                      onTap: () => _connect(device),
                    );
                  },
                ),
              ),
            if (_printers.isConnected(widget.role))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _loading ? null : () => _disconnect(),
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('Disconnect'),
                ),
              )
            else if (_printers.deviceName(widget.role) != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _loading ? null : () => _disconnect(forget: true),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Forget saved printer'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
