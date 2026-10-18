import 'package:flutter/material.dart';

class PosAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? sectionTitle;
  final bool isVoidRequestPending;
  final bool showPrintButton;
  final String syncStatus;
  final Color syncDotColor;
  final VoidCallback onPrint;
  final VoidCallback onSync;

  const PosAppBar({
    super.key,
    this.sectionTitle,
    required this.isVoidRequestPending,
    this.showPrintButton = true,
    required this.syncStatus,
    required this.syncDotColor,
    required this.onPrint,
    required this.onSync,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.black,
      elevation: 0,
      leading: Builder(
        builder: (context) => IconButton(
          tooltip: 'Open navigation menu',
          icon: const Icon(Icons.menu, color: Colors.white, size: 22),
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      titleSpacing: 0,
      title: Text(
        sectionTitle ?? 'POS',
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFFCFD5DF),
        ),
      ),
      actions: [
        if (showPrintButton)
          TextButton(
            onPressed: isVoidRequestPending ? null : onPrint,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white38,
              side: const BorderSide(color: Colors.white54),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Print', style: TextStyle(fontSize: 12)),
          ),
        if (showPrintButton) const SizedBox(width: 6),
        InkWell(
          onTap: onSync,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: syncDotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  syncStatus,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
