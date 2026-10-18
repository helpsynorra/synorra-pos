// ignore_for_file: deprecated_member_use, unused_field

import 'package:flutter/material.dart';

enum PosSection { terminal, stock, restock }

typedef PosDrawerBuilder = Widget Function(PosSection section);

class PosNavigationDrawer extends StatelessWidget {
  final PosSection selectedSection;
  final String cashierName;
  final String labelsConnection;
  final String receiptConnection;
  final String syncStatus;
  final bool canLogout;
  final bool inventoryFeaturesEnabled;
  final bool stockInventoryEnabled;
  final bool restockInventoryEnabled;
  final bool connectLabelsEnabled;
  final bool connectReceiptEnabled;
  final String logoutDisabledMessage;
  final VoidCallback onOpenTerminal;
  final VoidCallback onOpenStock;
  final VoidCallback onOpenRestock;
  final VoidCallback onOpenBaristas;
  final VoidCallback onOpenBackOffice;
  final VoidCallback onOpenHelpCenter;
  final VoidCallback onConnectLabels;
  final VoidCallback onConnectReceipt;
  final VoidCallback onSync;
  final VoidCallback onLogout;

  const PosNavigationDrawer({
    super.key,
    required this.selectedSection,
    required this.cashierName,
    required this.labelsConnection,
    required this.receiptConnection,
    required this.syncStatus,
    required this.canLogout,
    required this.inventoryFeaturesEnabled,
    required this.stockInventoryEnabled,
    required this.restockInventoryEnabled,
    required this.connectLabelsEnabled,
    required this.connectReceiptEnabled,
    required this.logoutDisabledMessage,
    required this.onOpenTerminal,
    required this.onOpenStock,
    required this.onOpenRestock,
    required this.onOpenBaristas,
    required this.onOpenBackOffice,
    required this.onOpenHelpCenter,
    required this.onConnectLabels,
    required this.onConnectReceipt,
    required this.onSync,
    required this.onLogout,
  });

  static const _navy = Color(0xFF111C30);
  static const _ink = Color(0xFF18263E);
  static const _muted = Color(0xFF71819B);
  static const _line = Color(0xFFE7ECF3);
  static const _active = Color(0xFFF0F4FA);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final drawerWidth = (width * .76).clamp(290.0, 420.0).toDouble();
    final isOnline = syncStatus.toLowerCase().contains('online');

    return Drawer(
      width: drawerWidth,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                children: [
                  _sectionLabel('MAIN'),
                  _row(
                    icon: Icons.point_of_sale_outlined,
                    title: 'POS Terminal',
                    selected: selectedSection == PosSection.terminal,
                    onTap: () =>
                        _select(context, PosSection.terminal, onOpenTerminal),
                  ),
                  if (inventoryFeaturesEnabled &&
                      (stockInventoryEnabled || restockInventoryEnabled)) ...[
                    const SizedBox(height: 20),
                    _sectionLabel('INVENTORY'),
                    if (stockInventoryEnabled)
                      _row(
                        icon: Icons.inventory_2_outlined,
                        title: 'Stock inventory',
                        selected: selectedSection == PosSection.stock,
                        onTap: () =>
                            _select(context, PosSection.stock, onOpenStock),
                      ),
                    if (restockInventoryEnabled)
                      _row(
                        icon: Icons.add_shopping_cart_outlined,
                        title: 'Restock inventory',
                        selected: selectedSection == PosSection.restock,
                        onTap: () =>
                            _select(context, PosSection.restock, onOpenRestock),
                      ),
                  ],
                  const SizedBox(height: 20),
                  _sectionLabel('STAFF & SHIFT'),
                  _row(
                    icon: Icons.groups_outlined,
                    title: 'Staff on Shift / Team',
                    onTap: () => _closeThen(context, onOpenBaristas),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('SALES & ADMIN'),
                  _row(
                    icon: Icons.apartment_outlined,
                    title: 'Back Office',
                    subtitle: 'Inventory, Reports, Analytics',
                    onTap: () => _closeThen(context, onOpenBackOffice),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('SUPPORT'),
                  _row(
                    icon: Icons.contact_support_outlined,
                    title: 'Support',
                    onTap: () => _closeThen(context, onOpenHelpCenter),
                  ),
                  if (connectLabelsEnabled || connectReceiptEnabled) ...[
                    if (connectLabelsEnabled)
                      _row(
                        icon: Icons.local_cafe_outlined,
                        title: 'Connect labels',
                        subtitle: labelsConnection,
                        onTap: () => _closeThen(context, onConnectLabels),
                      ),
                    if (connectReceiptEnabled)
                      _row(
                        icon: Icons.receipt_long_outlined,
                        title: 'Connect receipt',
                        subtitle: receiptConnection,
                        onTap: () => _closeThen(context, onConnectReceipt),
                      ),
                  ],
                  const SizedBox(height: 20),
                  _sectionLabel('SYSTEM STATUS'),
                  _row(
                    icon: Icons.sync_rounded,
                    title: syncStatus.toLowerCase().contains('online')
                        ? 'Sync Online'
                        : 'Sync Offline',
                    leadingDot: isOnline
                        ? const Color(0xFF32C66A)
                        : const Color(0xFFF0A33A),
                    onTap: () => _closeThen(context, onSync),
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 18, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF101827), Color(0xFF202D43)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Owner: $cashierName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD0DBEA),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: .2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: canLogout ? 'Logout' : logoutDisabledMessage,
                child: Material(
                  color: Colors.white.withOpacity(.12),
                  borderRadius: BorderRadius.circular(30),
                  child: InkWell(
                    onTap:
                        canLogout ? () => _closeThen(context, onLogout) : null,
                    borderRadius: BorderRadius.circular(30),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.logout_rounded,
                              size: 18,
                              color: canLogout ? Colors.white : Colors.white54),
                          const SizedBox(width: 7),
                          Text('Logout',
                              style: TextStyle(
                                color:
                                    canLogout ? Colors.white : Colors.white54,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Text(
          label,
          style: const TextStyle(
            color: _muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.35,
          ),
        ),
      );

  Widget _row({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    bool selected = false,
    bool destructive = false,
    Color? leadingDot,
  }) {
    final color = destructive ? const Color(0xFFEC3547) : _ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: destructive
            ? const Color(0xFFFFEFF1)
            : selected
                ? _active
                : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(icon, size: 25, color: color),
                if (leadingDot != null) ...[
                  const SizedBox(width: 12),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                        color: leadingDot, shape: BoxShape.circle),
                  ),
                ],
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                            color: color,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          )),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: destructive ? color : _muted,
                                fontSize: 11.5)),
                      ],
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

  Widget _footer() => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(22, 0, 22, 12),
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _line)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Image.asset(
                'lib/src/images/logo_wordmark.png',
                width: 84,
                height: 22,
                fit: BoxFit.contain,
                semanticLabel: 'Synorra',
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Powered by Synorra  ·  Version 1.0',
              style: TextStyle(color: _muted, fontSize: 11.5),
            ),
          ],
        ),
      );

  void _select(BuildContext context, PosSection section, VoidCallback action) {
    if (section == selectedSection) {
      Navigator.pop(context);
    } else {
      _closeThen(context, action);
    }
  }

  void _closeThen(BuildContext context, VoidCallback action) {
    Navigator.pop(context);
    action();
  }
}
