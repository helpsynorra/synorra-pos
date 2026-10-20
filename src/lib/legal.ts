export type LegalSection = {
  heading: string;
  body: string;
};

export const termsOfUse: LegalSection[] = [
  {
    heading: "Acceptance and roles",
    body: "Using Synorra POS means you accept these terms. The Merchant or Admin manages the store, pricing, inventory, reports, and staff access. Staff and cashiers may use only the operational features allowed by their assigned role and permissions.",
  },
  {
    heading: "Account security and responsibility",
    body: "Each user must keep their own username and password private and must not share accounts where individual accountability is required. Actions taken under an account, including orders, voids, staff activity, and stock changes, are attributed to that account. The Merchant or Admin must promptly disable accounts for former or transferred staff and protect the POS device when unattended.",
  },
  {
    heading: "Acceptable use",
    body: "Do not bypass access controls, attempt unauthorized privilege escalation, reverse engineer or disrupt the service, use it for unlawful or fraudulent transactions, share individual logins improperly, or alter or delete records to conceal activity. Report suspected account compromise to the Merchant or support promptly.",
  },
  {
    heading: "Merchant data and accuracy",
    body: "The Merchant is responsible for the accuracy of menu items, prices, tax settings, discounts, stock counts, and sales records, and for complying with applicable tax, invoicing, and consumer laws. Synorra POS records operational activity; it does not guarantee physical stock or cash-drawer accuracy and is not accounting, tax, or legal advice. The Merchant retains its store data. The service operator retains its rights in the software and interface; use of the service does not transfer software ownership.",
  },
  {
    heading: "Offline operation and availability",
    body: "Offline checkout may use cached data and queue changes for later synchronization. Pending changes can be delayed until connectivity returns. Review the sync status and reconcile records before switching stores or devices. Internet, power, device, printer, hosting, and third-party outages can interrupt service. The system is supplied on an as-available basis and no uptime SLA or guaranteed offline synchronization is currently offered.",
  },
  {
    heading: "Intellectual property and limits",
    body: "The Merchant remains responsible for keeping any legally required copies of business records. Reports, printing, and account deletion are subject to the features currently available; no separate export window or backup service is promised. To the extent permitted by law, the service is provided without guarantees beyond those expressly agreed in writing. The operator is not responsible for indirect losses caused by outages, incorrect configuration, inaccurate data, or user misuse. Nothing in these terms excludes liability that cannot legally be excluded.",
  },
  {
    heading: "Suspension and termination",
    body: "Access may be restricted to protect accounts or data, address security incidents, comply with law, or respond to a material breach. The Merchant may request account deletion through Support > Account. Before deletion, preserve any business records you are required to keep; deletion is permanent and the confirmation screen describes the data removed by the app.",
  },
  {
    heading: "Updates and contact",
    body: "These terms may be revised when the service changes. Continued use after a revision takes effect is subject to the updated terms, where permitted by law. Contact help.synorra@gmail.com with questions.",
  },
];

export const privacyPolicy: LegalSection[] = [
  {
    heading: "Customer data collected by the current POS",
    body: "The current POS does not provide customer-profile fields for customer name, phone, email, physical address, loyalty accounts, or digital invoices, and it does not send digital receipts. Do not enter such information into free-text fields unless the Merchant has a lawful purpose and has given the required notice. If a future feature collects customer details, this policy and the customer-facing notice must be updated before use.",
  },
  {
    heading: "Transaction and payment information",
    body: "The POS stores order items, totals, discounts or promotion labels, payment-method labels (Cash, GCash, or Maya), amounts paid and change, ticket numbers, timestamps, and void details. GCash and Maya are recorded as payment-method choices only; the current POS does not connect to a payment gateway or collect card numbers, CVV codes, or bank credentials. No PayMongo, Stripe, or other payment processor integration is configured in the current code. The POS does not record cash-drawer opening, closing, or cash-release events.",
  },
  {
    heading: "Staff, audit, and technical information",
    body: "Staff and Admin records may include name, username, email, role, permissions, and password credentials. The system records login/logout and shift activity, orders and void requests, inventory and restock changes, timestamps, and related staff identifiers. New or changed web passwords use bcrypt; legacy records may remain in the older format until they are upgraded. Mobile offline credentials use the device secure-storage facility. The app does not request a staff PIN or phone number. The app itself does not maintain an IP-address or browser-fingerprint profile; hosting providers may collect network, device, and access logs under their own notices.",
  },
  {
    heading: "Purposes of processing",
    body: "Information is used to authenticate users and apply role permissions; record sales, print receipts and labels, apply discounts, manage inventory and restocks, generate operational reports, attribute voids and staff activity, synchronize offline changes, secure accounts, and troubleshoot the service. The current system does not provide customer loyalty or marketing features.",
  },
  {
    heading: "Sharing and service providers",
    body: "Store records are synchronized with the Supabase project configured for Synorra POS. The website is hosted through Vercel. Gmail SMTP is used to send Owner password-reset emails. The app can connect to Bluetooth printers to print selected order information. No payment-gateway or customer SMS/email-receipt provider is integrated in the current code. Information may also be disclosed when required by a valid legal request. Confirm the providers and their data-processing terms for your deployment.",
  },
  {
    heading: "Storage and security",
    body: "Network requests use HTTPS when the deployed service supports it. New or changed web passwords use bcrypt and web sessions are signed, HttpOnly cookies with a 12-hour expiry. Role-based permissions restrict available features. Mobile offline credentials use platform secure storage, but other operational data and pending queues are cached in local app preferences and are not encrypted by the app; secure the POS device with a screen lock and limit physical access. The app does not currently enforce automatic idle logout. Activity records are not guaranteed to be immutable, and the current system includes record-deletion controls; do not rely on them as a tamper-proof legal audit log. Cloud-at-rest encryption and backup frequency/retention depend on the configured Supabase/Vercel plans and settings and have not been verified by this app; do not assume a daily encrypted backup is enabled.",
  },
  {
    heading: "Retention and deletion",
    body: "The current code does not set an automatic retention or archival schedule. Store and audit records remain in local or cloud storage until deleted through available account or record-management functions, subject to provider backup cycles. Merchants must preserve records for any applicable legal and tax period. In the Philippines, RA 11976 amended the general preservation period for books of accounts and other accounting records to five years, subject to its terms and exceptions; obtain tax advice for your business and keep any required records before deleting an account. The POS does not automatically enforce that retention period.",
  },
  {
    heading: "Data subject rights and requests",
    body: "Staff and other individuals may contact the responsible business to request information about, access to, or correction of personal data, or to ask about deletion/blocking. The account owner can manage staff accounts and request Owner-account deletion in Support > Account. Deletion may be limited where records must be retained by law or are needed for legal claims. The current POS does not store customer profiles; customer requests about information collected outside the POS should be directed to the business that collected it.",
  },
  {
    heading: "Privacy contact",
    body: "Service name: Synorra POS. For privacy inquiries or data requests, email help.synorra@gmail.com or call +63 981 772 6937. The legal operating entity and appointed Data Protection Officer/Privacy Lead are not identified in the system configuration; the operator must confirm and publish those details before treating this draft as the official privacy notice.",
  },
];

export const cookiePolicy: LegalSection[] = [
  {
    heading: "Essential sign-in cookie",
    body: "The Synorra POS website uses an essential cookie named synorra_session to keep an authenticated staff session and apply role-based access. It is set after sign-in, marked HttpOnly, and expires after 12 hours. In secure production environments it is also marked Secure. The cookie is not used for advertising.",
  },
  {
    heading: "No analytics cookies currently configured",
    body: "The current website code does not configure analytics or advertising cookies. If this changes, this policy and any consent choices required for the new technologies will be updated before they are enabled.",
  },
  {
    heading: "Managing cookies",
    body: "You can remove or block cookies in your browser settings. Blocking the essential sign-in cookie may prevent you from signing in or using protected POS and back-office pages. Removing it signs you out; you can sign in again to create a new session.",
  },
  {
    heading: "Contact",
    body: "For questions about cookies or website privacy, contact help.synorra@gmail.com. See the Privacy Policy for information about account and store data handled by Synorra POS.",
  },
];
