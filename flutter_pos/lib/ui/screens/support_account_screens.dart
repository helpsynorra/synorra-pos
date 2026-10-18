import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help Center')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'How can we help?',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Find quick instructions for using Synorra POS or get in touch with support.',
            style: TextStyle(color: Color(0xFF667085), height: 1.5),
          ),
          const SizedBox(height: 22),
          _HelpCard(
            icon: Icons.menu_book_outlined,
            title: 'User Guide',
            subtitle: 'Checkout, menu, inventory, restocking, and staff shifts',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const UserGuideScreen(),
            )),
          ),
          const SizedBox(height: 12),
          _HelpCard(
            icon: Icons.groups_outlined,
            title: 'Community',
            subtitle: 'Connect with Synorra and share feedback',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const CommunityScreen(),
            )),
          ),
          const SizedBox(height: 12),
          _HelpCard(
            icon: Icons.mail_outline,
            title: 'Contact support',
            subtitle: 'Email help.synorra@gmail.com',
            onTap: () => _launch(context, Uri(scheme: 'mailto', path: 'help.synorra@gmail.com')),
          ),
        ],
      ),
    );
  }
}

class UserGuideScreen extends StatelessWidget {
  const UserGuideScreen({super.key});

  static const _sections = <(IconData, String, String)>[
    (Icons.point_of_sale_outlined, 'Take an order', 'Choose a menu item, select its options, add it to the cart, then review the total and payment method before completing checkout.'),
    (Icons.restaurant_menu_outlined, 'Manage your menu', 'Open Back office to add or update categories, products, prices, and availability. Changes are stored for your Owner account.'),
    (Icons.inventory_2_outlined, 'Track inventory', 'Use Stock inventory to review ingredients and current quantities. Configure recipes in Back office so sales can deduct the ingredients you use.'),
    (Icons.add_shopping_cart_outlined, 'Record a restock', 'Open Restock inventory, choose the ingredient, enter the quantity received, and save. The stock total updates with the restock.'),
    (Icons.badge_outlined, 'Manage a shift', 'Use Baristas on shift to record who is working. Staff permissions and accounts are managed from Back office.'),
    (Icons.sync_outlined, 'Check sync and printing', 'The drawer shows connection status and printer settings. Reconnect to the internet to sync changes if the POS was offline.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Guide')),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _sections.length,
        separatorBuilder: (_, __) => const Divider(height: 24),
        itemBuilder: (context, index) {
          final (icon, title, description) = _sections[index];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: const Color(0xFF263B2A)),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(description, style: const TextStyle(height: 1.45)),
            ),
          );
        },
      ),
    );
  }
}

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Community')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.groups_outlined, size: 54, color: Color(0xFF263B2A)),
              const SizedBox(height: 18),
              const Text('Grow with Synorra', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              const Text(
                'Share feedback, ask questions, and tell us what would make your shop easier to run. Email the Synorra team and we’ll point you to the right place to connect.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF667085), height: 1.5),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _launch(context, Uri(scheme: 'mailto', path: 'help.synorra@gmail.com', queryParameters: {'subject': 'Synorra community'})),
                icon: const Icon(Icons.mail_outline),
                label: const Text('Contact Synorra'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DeleteOwnerAccountScreen extends StatefulWidget {
  final Future<void> Function(String password) onDelete;

  const DeleteOwnerAccountScreen({super.key, required this.onDelete});

  @override
  State<DeleteOwnerAccountScreen> createState() => _DeleteOwnerAccountScreenState();
}

class _DeleteOwnerAccountScreenState extends State<DeleteOwnerAccountScreen> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _isDeleting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    if (_confirmationController.text.trim() != 'DELETE MY ACCOUNT') {
      setState(() => _error = 'Type DELETE MY ACCOUNT exactly to continue.');
      return;
    }
    if (_passwordController.text.isEmpty) {
      setState(() => _error = 'Enter your current password to verify it’s you.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete this Owner account?'),
        content: const Text(
          'This permanently deletes the Owner account and its sales, menu, inventory, recipes, restocks, staff, and store settings. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep account')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isDeleting = true;
      _error = null;
    });
    try {
      await widget.onDelete(_passwordController.text);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(Icons.warning_amber_rounded, size: 52, color: Colors.red.shade700),
          const SizedBox(height: 12),
          const Text('Delete your Owner account', textAlign: TextAlign.center, style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text(
            'Deleting permanently removes this account and all data for its store, including sales history, menu, inventory, recipes, restocks, staff accounts, and settings. You will be signed out. This action cannot be reversed.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF667085), height: 1.5),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Current password', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _confirmationController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Type DELETE MY ACCOUNT to confirm',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _isDeleting ? null : _confirmDelete,
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700, padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: _isDeleting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.delete_forever_outlined),
            label: Text(_isDeleting ? 'Deleting…' : 'Delete permanently'),
          ),
        ],
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HelpCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE4E7EC)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: const Color(0xFF263B2A)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

Future<void> _launch(BuildContext context, Uri uri) async {
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open that link.')));
    }
  } on PlatformException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open that link.')));
    }
  }
}
