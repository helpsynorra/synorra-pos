// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/menu_item.dart';
import '../models/order.dart';
import 'printer_service.dart';

enum PrinterRole { slip, labels }

enum LabelPrinterLanguage { tspl, cpcl }

class BluetoothPrinterService extends ChangeNotifier {
  BluetoothPrinterService._();

  static final BluetoothPrinterService instance = BluetoothPrinterService._();
  static const _slipAddressKey = 'synorra_slip_printer_address';
  static const _slipNameKey = 'synorra_slip_printer_name';
  static const _labelsAddressKey = 'synorra_labels_printer_address';
  static const _labelsNameKey = 'synorra_labels_printer_name';
  static const _labelsLanguageKey = 'synorra_labels_printer_language';

  final FlutterClassicBluetooth _bluetooth = FlutterClassicBluetooth();
  final Map<PrinterRole, BtcConnection> _connections = {};
  String? _slipAddress;
  String? _slipName;
  String? _labelsAddress;
  String? _labelsName;
  LabelPrinterLanguage _labelLanguage = LabelPrinterLanguage.tspl;
  bool _initialized = false;

  bool isConnected(PrinterRole role) =>
      _connections[role]?.isConnected ?? false;

  String? deviceName(PrinterRole role) =>
      role == PrinterRole.slip ? _slipName : _labelsName;

  LabelPrinterLanguage get labelLanguage => _labelLanguage;

  String connectionSummary(PrinterRole role) {
    final name = deviceName(role);
    if (isConnected(role)) return 'Connected: ${name ?? 'Bluetooth printer'}';
    return name == null
        ? 'No printer connected'
        : 'Saved: $name (disconnected)';
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final preferences = await SharedPreferences.getInstance();
    _slipAddress = preferences.getString(_slipAddressKey);
    _slipName = preferences.getString(_slipNameKey);
    _labelsAddress = preferences.getString(_labelsAddressKey);
    _labelsName = preferences.getString(_labelsNameKey);
    _labelLanguage = LabelPrinterLanguage.values.firstWhere(
      (language) => language.name == preferences.getString(_labelsLanguageKey),
      orElse: () => LabelPrinterLanguage.tspl,
    );
    notifyListeners();

    if (_slipAddress == null && _labelsAddress == null) return;
    try {
      final paired = await _bluetooth.getPairedDevices();
      for (final role in PrinterRole.values) {
        final address =
            role == PrinterRole.slip ? _slipAddress : _labelsAddress;
        if (address == null) continue;
        final device =
            paired.where((item) => item.address == address).firstOrNull;
        if (device != null) {
          _connections[role] = await _bluetooth.connect(address: address);
        }
      }
    } catch (_) {
      // The saved device can be unavailable or Bluetooth permission can be missing.
    }
    notifyListeners();
  }

  Future<void> connect(
    PrinterRole role,
    BtcDevice device, {
    LabelPrinterLanguage? language,
  }) async {
    final permission = await _bluetooth.requestPermissions(
      permissions: {BtcPermission.connect},
    );
    if (permission != BtcPermissionStatus.granted &&
        permission != BtcPermissionStatus.notRequired) {
      throw StateError(
          'Bluetooth permission is required to connect a printer.');
    }

    if (device.bondState != BtcBondState.bonded) {
      final paired = await _bluetooth.bondDevice(device.address);
      if (!paired)
        throw StateError('Pairing with ${device.displayName} failed.');
    }

    await disconnect(role, clearSaved: false, notify: false);
    final connection = await _bluetooth.connect(
      address: device.address,
      timeout: const Duration(seconds: 15),
    );
    _connections[role] = connection;

    final preferences = await SharedPreferences.getInstance();
    if (role == PrinterRole.slip) {
      _slipAddress = device.address;
      _slipName = device.displayName;
      await preferences.setString(_slipAddressKey, device.address);
      await preferences.setString(_slipNameKey, device.displayName);
    } else {
      _labelsAddress = device.address;
      _labelsName = device.displayName;
      await preferences.setString(_labelsAddressKey, device.address);
      await preferences.setString(_labelsNameKey, device.displayName);
      if (language != null) _labelLanguage = language;
      await preferences.setString(_labelsLanguageKey, _labelLanguage.name);
    }
    notifyListeners();
  }

  Future<void> disconnect(
    PrinterRole role, {
    bool clearSaved = false,
    bool notify = true,
  }) async {
    final connection = _connections.remove(role);
    if (connection != null) {
      try {
        await connection.finish();
      } finally {
        connection.dispose();
      }
    }
    if (clearSaved) {
      final preferences = await SharedPreferences.getInstance();
      if (role == PrinterRole.slip) {
        _slipAddress = null;
        _slipName = null;
        await preferences.remove(_slipAddressKey);
        await preferences.remove(_slipNameKey);
      } else {
        _labelsAddress = null;
        _labelsName = null;
        await preferences.remove(_labelsAddressKey);
        await preferences.remove(_labelsNameKey);
      }
    }
    if (notify) notifyListeners();
  }

  Future<void> printslip(
    Order order, {
    bool includeinternalCopy = true,
  }) async {
    final connection = _connections[PrinterRole.slip];
    if (connection == null || !connection.isConnected) {
      throw StateError('Connect a slip printer from the POS menu first.');
    }
    final bytes = <int>[
      0x1B,
      0x40,
      if (includeinternalCopy) ...[
        ...utf8.encode(
          PrinterService.formatslip(order, includePrinterCommands: true),
        ),
        0x0A,
      ],
      0x1D,
      0x56,
      0x41,
      0x03,
    ];
    await connection.output.writeBytes(bytes);
  }

  Future<void> printLabels(
    Order order, {
    required List<MenuItem> menu,
  }) async {
    final connection = _connections[PrinterRole.labels];
    if (connection == null || !connection.isConnected) {
      throw StateError('Connect a label printer from the POS menu first.');
    }

    for (final itemIndex in PrinterService.cupLabelItemIndexes(order, menu)) {
      final commands = _labelLanguage == LabelPrinterLanguage.tspl
          ? _tsplLabel(order, itemIndex)
          : _cpclLabel(order, itemIndex);
      await connection.output.writeBytes(utf8.encode(commands));
    }
  }

  String _tsplLabel(Order order, int itemIndex) {
    final lines = _labelLines(order, itemIndex);
    final commands = StringBuffer()
      ..writeln('SIZE 58 mm,30 mm')
      ..writeln('GAP 2 mm,0')
      ..writeln('DIRECTION 1')
      ..writeln('CLS');
    var y = 16;
    for (var index = 0; index < lines.length; index++) {
      final isOptionsLine = index == 5;
      final font = isOptionsLine ? '1' : '3';
      final x = isOptionsLine ? 4 : 16;
      commands.writeln('TEXT $x,$y,"$font",0,1,1,"${_quote(lines[index])}"');
      y += index == 0
          ? 30
          : isOptionsLine
              ? 18
              : 25;
    }
    commands
      ..writeln('PRINT 1,1')
      ..writeln();
    return commands.toString();
  }

  String _cpclLabel(Order order, int itemIndex) {
    final lines = _labelLines(order, itemIndex);
    final commands = StringBuffer()
      ..writeln('! 0 200 200 240 1')
      ..writeln('PAGE-WIDTH 464');
    var y = 16;
    for (var index = 0; index < lines.length; index++) {
      final isOptionsLine = index == 5;
      final font = isOptionsLine ? 0 : 4;
      final x = isOptionsLine ? 8 : 16;
      commands.writeln('TEXT $font 0 $x $y "${_quote(lines[index])}"');
      y += index == 0
          ? 34
          : isOptionsLine
              ? 18
              : 28;
    }
    commands
      ..writeln('FORM')
      ..writeln('PRINT')
      ..writeln();
    return commands.toString();
  }

  List<String> _labelLines(Order order, int itemIndex) {
    return PrinterService.formatCupLabel(order, itemIndex)
        .trimRight()
        .split('\n');
  }

  String _quote(String value) =>
      value.replaceAll('"', "'").replaceAll(RegExp(r'[\r\n\x00-\x1F]'), ' ');
}
