// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportHubScreen extends StatelessWidget {
  final VoidCallback onOpenDeleteAccount;
  final bool canDeleteOwnerAccount;

  const SupportHubScreen({
    super.key,
    required this.onOpenDeleteAccount,
    required this.canDeleteOwnerAccount,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('How can we help?',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
              'Find help, review Synorra legal information, or manage your account.',
              style: TextStyle(color: Color(0xFF667085), height: 1.5)),
          const SizedBox(height: 22),
          _HelpCard(
            icon: Icons.help_outline_rounded,
            title: 'Help Center',
            subtitle: 'User guide, contact support, and community',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const HelpCenterScreen(),
            )),
          ),
          const SizedBox(height: 12),
          _HelpCard(
            icon: Icons.gavel_outlined,
            title: 'Legal Information',
            subtitle: 'Terms of use and privacy policy',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const LegalInformationScreen(),
            )),
          ),
          const SizedBox(height: 12),
          _HelpCard(
            icon: Icons.manage_accounts_outlined,
            title: 'Account',
            subtitle: 'Account security and deletion',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => AccountSupportScreen(
                canDeleteOwnerAccount: canDeleteOwnerAccount,
                onDeleteAccount: onOpenDeleteAccount,
              ),
            )),
          ),
        ],
      ),
    );
  }
}

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
            icon: Icons.mail_outline,
            title: 'Contact support',
            subtitle: 'Email help.synorra@gmail.com',
            onTap: () => _launch(
                context, Uri(scheme: 'mailto', path: 'help.synorra@gmail.com')),
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
        ],
      ),
    );
  }
}

class LegalInformationScreen extends StatelessWidget {
  const LegalInformationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Legal Information')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Synorra policies',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text(
              'Choose a document. Contact Synorra support for the latest official version.',
              style: TextStyle(color: Color(0xFF667085), height: 1.5)),
          const SizedBox(height: 20),
          _HelpCard(
            icon: Icons.description_outlined,
            title: 'Terms of Use',
            subtitle: 'Service terms and acceptable use',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const LegalDocumentScreen(
                title: 'Terms of Use',
              ),
            )),
          ),
          const SizedBox(height: 12),
          _HelpCard(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            subtitle: 'How account and store information is handled',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const LegalDocumentScreen(
                title: 'Privacy Policy',
              ),
            )),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => _launch(
                context,
                Uri(
                    scheme: 'mailto',
                    path: 'help.synorra@gmail.com',
                    queryParameters: {'subject': 'Synorra legal information'})),
            icon: const Icon(Icons.mail_outline),
            label: const Text('Ask Synorra support'),
          ),
        ],
      ),
    );
  }
}

class LegalDocumentScreen extends StatelessWidget {
  final String title;

  const LegalDocumentScreen({super.key, required this.title});

  static const _termsSections = <(String, String)>[
    (
      'Acceptance and roles',
      'Using Synorra POS means you accept these terms. The Merchant or Admin manages the store, pricing, inventory, reports, and staff access. Staff and cashiers may use only the operational features allowed by their assigned role and permissions.'
    ),
    (
      'Account security and responsibility',
      'Each user must keep their own username and password private and must not share accounts where individual accountability is required. Actions taken under an account, including orders, voids, staff activity, and stock changes, are attributed to that account. The Merchant or Admin must promptly disable accounts for former or transferred staff and protect the POS device when unattended.'
    ),
    (
      'Acceptable use',
      'Do not bypass access controls, attempt unauthorized privilege escalation, reverse engineer or disrupt the service, use it for unlawful or fraudulent transactions, share individual logins improperly, or alter or delete records to conceal activity. Report suspected account compromise to the Merchant or support promptly.'
    ),
    (
      'Merchant data and accuracy',
      'The Merchant is responsible for the accuracy of menu items, prices, tax settings, discounts, stock counts, and sales records, and for complying with applicable tax, invoicing, and consumer laws. Synorra POS records operational activity; it does not guarantee physical stock or cash-drawer accuracy and is not accounting, tax, or legal advice. The Merchant retains its store data. The service operator retains its rights in the software and interface; use of the service does not transfer software ownership.'
    ),
    (
      'Internal management tool and tax responsibility',
      'Synorra POS is an operational and internal-management tool. Internal order slips are intended for store operations, not as BIR-compliant fiscal slips; exact printed content depends on the configured feature and printer settings. Synorra is not a tax-filing agent or BIR compliance officer. The Merchant is responsible for business registration (including BIR Form 2303), obtaining any required Authority to Print for manual slips or Permit to Use for electronic POS systems, and complying with applicable tax, invoicing, and consumer laws.'
    ),
    (
      'Database migrations and self-managed deployments',
      'Some Finance and shift-management features require corresponding Supabase database migrations or schema updates. On self-managed deployments, the Merchant or administrator is responsible for applying required updates. Features may be unavailable or experience errors when updates have not been applied.'
    ),
    (
      'Camera attendance and personal information',
      'Where the Merchant enables photo attendance, users may be asked to provide a live photo at clock-in and clock-out. These images are used solely for store timekeeping and attendance photo verification; Synorra POS does not use facial recognition technology. The Merchant is responsible for informing staff, configuring attendance appropriately, limiting access to attendance records, and handling personal information under applicable privacy requirements, including the Philippine Data Privacy Act of 2012 (RA 10173).'
    ),
    (
      'Offline operation, order slips, and availability',
      'Synorra POS supports local offline transaction queueing. Offline operations depend on local device storage and device integrity; queued changes may remain pending until the device reconnects. The Merchant is responsible for reviewing synchronization status and reconciling records. Synorra is not responsible for loss caused by cleared browser or app data, device damage, or failure to reconnect and synchronize offline queues. Internet, power, device, printer, hosting, and third-party outages can interrupt service. The Service is provided on an as-is and as-available basis; no uptime service-level agreement or guaranteed offline synchronization is offered.'
    ),
    (
      'Intellectual property and limits',
      'The Merchant must keep any business records required by law and verify slip, tax, and regulatory settings with qualified advisers. To the extent permitted by law, Synorra and its founders and developers are not liable for BIR tax-mapping penalties, audit fines, business closures, or revenue losses caused by service interruptions, internet outages, hardware or printer failures, or cashier errors. The Merchant remains responsible for its own configuration and operations. Nothing in these Terms excludes liability that cannot legally be excluded.'
    ),
    (
      'Suspension and termination',
      'Access may be restricted to protect accounts or data, address security incidents, comply with law, or respond to a material breach. The Merchant may request account deletion through Support > Account. Before deletion, preserve any business records you are required to keep; deletion is permanent and the confirmation screen describes the data removed by the app.'
    ),
    (
      'Updates and contact',
      'These Terms are governed by the laws of the Republic of the Philippines, including the Civil Code, the E-Commerce Act (RA 8792), and the Consumer Act (RA 7394), as applicable. These Terms may be revised when the Service changes. Contact help.synorra@gmail.com with questions.'
    ),
  ];

  static const _privacySections = <(String, String)>[
    (
      'internal data collected by the current POS',
      'The current POS does not provide internal-profile fields for internal name, phone, email, physical address, loyalty accounts, or digital invoices, and it does not send digital slips. Do not enter such information into free-text fields unless the Merchant has a lawful purpose and has given the required notice. If a future feature collects internal details, this policy and the internal-facing notice must be updated before use.'
    ),
    (
      'Transaction and payment information',
      'The POS stores order items, totals, discounts or promotion labels, payment-method labels (Cash, GCash, or Maya), amounts paid and change, ticket numbers, timestamps, and void details. GCash and Maya are recorded as payment-method choices only; the current POS does not connect to a payment gateway or collect card numbers, CVV codes, or bank credentials. No PayMongo, Stripe, or other payment processor integration is configured in the current code. Finance features may also record shift opening floats, closing cash counts, sales totals, and cash expenses.'
    ),
    (
      'Staff, audit, and technical information',
      'Staff and Admin records may include name, username, email, role, permissions, password credentials, and Terms of Use consent metadata. The system records login/logout and shift activity, orders and void requests, inventory and restock changes, timestamps, and related staff identifiers. Where an owner enables photo attendance, the device captures and uploads a live photo with the clock-in or clock-out record for store timekeeping and photo verification. Synorra POS does not use facial recognition technology. New or changed web passwords use bcrypt; legacy records may remain in the older format until they are upgraded. Mobile offline credentials use the device secure-storage facility. The app does not request a staff phone number. The app itself does not maintain an IP-address or browser-fingerprint profile; hosting providers may collect network, device, and access logs under their own notices.'
    ),
    (
      'Purposes of processing',
      'Information is used to authenticate users and apply role permissions; record sales, print internal order slips and other operational documents, apply discounts, manage inventory and restocks, generate operational and finance reports, attribute voids and staff activity, verify attendance using staff-selected photo modes, synchronize offline changes, secure accounts, and troubleshoot the service. Attendance photos are used solely for store timekeeping and photo verification; the system does not use facial recognition. The current system does not provide internal loyalty or marketing features.'
    ),
    (
      'Sharing and service providers',
      'Synorra POS does not sell, trade, or rent personal information or store sales history to third parties for marketing. Store records are synchronized with the Supabase project configured for Synorra POS; the website is hosted through Vercel; and Gmail SMTP is used to send Owner password-reset emails. The app can connect to Bluetooth printers to print selected order information. Information may also be disclosed when required by a valid legal request. Confirm the providers and their data-processing terms for your deployment.'
    ),
    (
      'Storage and security',
      'Network requests use HTTPS when the deployed service supports it. New or changed web passwords use bcrypt and web sessions are signed, HttpOnly cookies with a 12-hour expiry. Role-based permissions restrict available features. Mobile offline credentials use platform secure storage, but other operational data and pending queues are cached in local app preferences and are not encrypted by the app; secure the POS device with a screen lock and limit physical access. The app does not currently enforce automatic idle logout. Activity records are not guaranteed to be immutable, and the current system includes record-deletion controls; do not rely on them as a tamper-proof legal audit log. Cloud-at-rest encryption and backup frequency/retention depend on the configured Supabase/Vercel plans and settings and have not been verified by this app; do not assume a daily encrypted backup is enabled.'
    ),
    (
      'Retention and deletion',
      'The current code does not set an automatic retention schedule tied to a subscription, nor does it provide a full-store data export feature. Some reports, including attendance summaries, can be downloaded in CSV format. Account and record deletion are subject to the features currently available; Owner-account deletion permanently removes store data. Preserve records required by law before deleting data. In the Philippines, RA 11976 amended the general preservation period for books of accounts and other accounting records to five years, subject to its terms and exceptions; obtain tax advice for your business.'
    ),
    (
      'Data subject rights and requests',
      'Staff and other individuals may contact the responsible business to request information about, access to, or correction of personal data, or to ask about deletion/blocking. The account owner can manage staff accounts and request Owner-account deletion in Support > Account. Deletion may be limited where records must be retained by law or are needed for legal claims. The current POS does not store internal profiles; internal requests about information collected outside the POS should be directed to the business that collected it.'
    ),
    (
      'Privacy contact',
      'For privacy inquiries or data-subject requests, contact the Synorra POS developer team at help.synorra@gmail.com. Service contact location: Zamboanga City, Philippines. The operator should confirm and publish the designated Compliance Officer for Privacy (COP) and legal entity details before treating this notice as final.'
    ),
    (
      'Camera attendance',
      'When a store selects an attendance mode that requires a photo, the POS captures a live image at clock-in and clock-out and stores it privately with the attendance record in the configured Supabase storage. The photo is used solely for store timekeeping and attendance photo verification. Synorra POS does not use facial recognition technology. The current code does not set an automatic attendance-photo retention schedule; the responsible business should manage access and retention in accordance with applicable requirements.'
    ),
    (
      'Philippine privacy framework',
      'Personal information is handled with reference to the Philippine Data Privacy Act of 2012 (Republic Act No. 10173) and its implementing rules. The business using Synorra POS is responsible for determining and documenting its lawful basis, providing required notices, limiting collection and retention, securing access, and responding to data-subject requests. This statement is not a certification of legal compliance. The legal entity of the service operator and its appointed Data Protection Officer/Privacy Lead must be confirmed and published by the operator.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final sections =
        title == 'Terms of Use' ? _termsSections : _privacySections;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
              title == 'Terms of Use'
                  ? Icons.description_outlined
                  : Icons.privacy_tip_outlined,
              size: 46,
              color: const Color(0xFF29476F)),
          const SizedBox(height: 18),
          Text(title,
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text(
            'Synorra POS · Last updated October 25, 2026',
            style: TextStyle(
              color: Color(0xFF667085),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          for (final (heading, body) in sections) ...[
            Text(heading,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            Text(body,
                style: const TextStyle(color: Color(0xFF667085), height: 1.6)),
            const SizedBox(height: 18),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _launch(
                context,
                Uri(
                    scheme: 'mailto',
                    path: 'help.synorra@gmail.com',
                    queryParameters: {'subject': 'Request: $title'})),
            icon: const Icon(Icons.mail_outline),
            label: const Text('Ask Synorra support'),
          ),
        ],
      ),
    );
  }
}

class AccountSupportScreen extends StatelessWidget {
  final bool canDeleteOwnerAccount;
  final VoidCallback onDeleteAccount;

  const AccountSupportScreen({
    super.key,
    required this.canDeleteOwnerAccount,
    required this.onDeleteAccount,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.manage_accounts_outlined,
              size: 48, color: Color(0xFF29476F)),
          const SizedBox(height: 14),
          const Text('Account & security',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text(
              'Manage your Synorra account. Deleting the Owner account permanently removes its store data and cannot be undone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF667085), height: 1.5)),
          const SizedBox(height: 24),
          Card(
            color: const Color(0xFFFFEFF1),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: const Icon(Icons.delete_forever_outlined,
                  color: Color(0xFFEC3547)),
              title: const Text('Delete account',
                  style: TextStyle(
                      color: Color(0xFFEC3547), fontWeight: FontWeight.w700)),
              subtitle: const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Permanently delete the account and its data'),
              ),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFFEC3547)),
              onTap: canDeleteOwnerAccount
                  ? onDeleteAccount
                  : () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Only the account owner can delete this account.')),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

class UserGuideScreen extends StatelessWidget {
  const UserGuideScreen({super.key});

  static const _sections = <(IconData, String, String)>[
    (
      Icons.point_of_sale_outlined,
      'Take an order',
      'Choose a menu item, select its options, add it to the cart, then review the total and payment method before completing checkout.'
    ),
    (
      Icons.restaurant_menu_outlined,
      'Manage your menu',
      'Open Back office to add or update categories, products, prices, and availability. Changes are stored for your Owner account.'
    ),
    (
      Icons.inventory_2_outlined,
      'Track inventory',
      'Use Stock inventory to review ingredients and current quantities. Configure recipes in Back office so sales can deduct the ingredients you use.'
    ),
    (
      Icons.add_shopping_cart_outlined,
      'Record a restock',
      'Open Restock inventory, choose the ingredient, enter the quantity received, and save. The stock total updates with the restock.'
    ),
    (
      Icons.badge_outlined,
      'Manage a shift',
      'Use Baristas on shift to record who is working. Staff permissions and accounts are managed from Back office.'
    ),
    (
      Icons.sync_outlined,
      'Check sync and printing',
      'The drawer shows connection status and printer settings. Reconnect to the internet to sync changes if the POS was offline.'
    ),
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
            leading: Icon(icon, color: const Color(0xFF29476F)),
            title: Text(title,
                style: const TextStyle(fontWeight: FontWeight.w700)),
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
              const Icon(Icons.groups_outlined,
                  size: 54, color: Color(0xFF29476F)),
              const SizedBox(height: 18),
              const Text('Grow with Synorra',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              const Text(
                'Share feedback, ask questions, and tell us what would make your shop easier to run. Email the Synorra team and we’ll point you to the right place to connect.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF667085), height: 1.5),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _launch(
                    context,
                    Uri(
                        scheme: 'mailto',
                        path: 'help.synorra@gmail.com',
                        queryParameters: {'subject': 'Synorra community'})),
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
  State<DeleteOwnerAccountScreen> createState() =>
      _DeleteOwnerAccountScreenState();
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
      setState(
          () => _error = 'Enter your current password to verify it’s you.');
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
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep account')),
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
      if (mounted)
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
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
          Icon(Icons.warning_amber_rounded,
              size: 52, color: Colors.red.shade700),
          const SizedBox(height: 12),
          const Text('Delete your Owner account',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
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
            decoration: const InputDecoration(
                labelText: 'Current password', border: OutlineInputBorder()),
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
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: _isDeleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
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

  const _HelpCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

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
        leading: Icon(icon, color: const Color(0xFF29476F)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
            padding: const EdgeInsets.only(top: 4), child: Text(subtitle)),
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
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that link.')));
    }
  } on PlatformException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open that link.')));
    }
  }
}
