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
  final VoidCallback onConnectLabels;
  final VoidCallback onConnectReceipt;
  final VoidCallback onSync;
  final VoidCallback onLogout;
  final VoidCallback onContactSupport;

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
    required this.onConnectLabels,
    required this.onConnectReceipt,
    required this.onSync,
    required this.onLogout,
    required this.onContactSupport,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
              color: Colors.black,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'synorra',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Owner: $cashierName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: canLogout ? onLogout : null,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Logout'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _destination(
                    context,
                    section: PosSection.terminal,
                    icon: Icons.point_of_sale_outlined,
                    label: 'POS Terminal',
                    onTap: onOpenTerminal,
                  ),
                  if (inventoryFeaturesEnabled && (stockInventoryEnabled || restockInventoryEnabled)) const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Text(
                      'INVENTORY',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  if (inventoryFeaturesEnabled && stockInventoryEnabled) _destination(
                    context,
                    section: PosSection.stock,
                    icon: Icons.inventory_2_outlined,
                    label: 'Stock inventory',
                    onTap: onOpenStock,
                  ),
                  if (inventoryFeaturesEnabled && restockInventoryEnabled) _destination(
                    context,
                    section: PosSection.restock,
                    icon: Icons.add_shopping_cart_outlined,
                    label: 'Restock inventory',
                    onTap: onOpenRestock,
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Text(
                      'BARISTA SHIFT',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.badge_outlined, color: Colors.black87),
                    title: const Text('Baristas on shift'),
                    onTap: () => _closeThen(context, onOpenBaristas),
                  ),
                   const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Text(
                      'Sales & Admin',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.open_in_new, color: Colors.black87),
                    title: const Text('Back office'),
                    onTap: () => _closeThen(context, onOpenBackOffice),
                  ),
                  if (connectLabelsEnabled || connectReceiptEnabled) const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Text(
                      'PRINTERS',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  if (connectLabelsEnabled) ListTile(
                    leading: const Icon(Icons.local_cafe_outlined,
                        color: Colors.black87),
                    title: const Text('Connect labels'),
                    subtitle: Text(labelsConnection),
                    onTap: () => _closeThen(context, onConnectLabels),
                  ),
                  if (connectReceiptEnabled) ListTile(
                    leading: const Icon(Icons.receipt_long_outlined,
                        color: Colors.black87),
                    title: const Text('Connect receipt'),
                    subtitle: Text(receiptConnection),
                    onTap: () => _closeThen(context, onConnectReceipt),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Text(
                      'SYNC STATUS',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.sync, color: Colors.black87),
                    title: const Text('Sync'),
                    subtitle: Text(syncStatus),
                    onTap: () => _closeThen(context, onSync),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        Text(
                          'Powered by Synorra',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Version 1.0',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Image.asset(
                    'lib/src/images/synorra.jpg',
                    width: 68,
                    height: 40,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: onContactSupport,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Contact Support',
                        style: TextStyle(
                          color: Color(0xFF374151),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _destination(
    BuildContext context, {
    required PosSection section,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isSelected = section == selectedSection;
    return ListTile(
      leading: Icon(icon,
          color: isSelected ? Colors.black : const Color(0xFF4B5563)),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      selected: isSelected,
      selectedTileColor: const Color(0xFFF3F4F6),
      onTap: () {
        if (isSelected) {
          Navigator.pop(context);
        } else {
          _closeThen(context, onTap);
        }
      },
    );
  }

  void _closeThen(BuildContext context, VoidCallback action) {
    Navigator.pop(context);
    action();
  }
}
