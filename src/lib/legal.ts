export type LegalSection = {
  heading: string;
  body: string;
};

export const termsOfUse: LegalSection[] = [
  {
    heading: "Acceptance and scope of service",
    body: "Welcome to Synorra POS. By registering, accessing, or using the Synorra application, Admin Console, Owner Workspace, or POS mobile application (the Service), you (the Merchant, Owner, or Client) agree to these Terms and Conditions (Terms). Do not use the Service if you do not agree. Synorra provides cloud and offline-capable beverage-shop management software for checkout, menu management, inventory tracking, staff scheduling, camera-based attendance, and financial reporting.",
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
    heading: "Internal management tool and tax responsibility",
    body: "Synorra POS is an operational and internal-management tool. Internal order slips are intended for store operations, not as BIR-compliant fiscal slips; the exact printed content depends on the configured feature and printer settings. Do not treat a printed slip as a compliant fiscal slip unless your business has confirmed that it meets applicable requirements. Synorra is not a tax-filing agent or BIR compliance officer. The Merchant is solely responsible for business registration (including BIR Form 2303), obtaining any required Authority to Print for manual slips or Permit to Use for electronic POS systems, and complying with applicable tax, invoicing, and consumer laws. The Merchant is responsible for accurate menu, pricing, tax, discount, stock, sales, and cash records. Synorra does not guarantee physical stock or cash-drawer accuracy and does not provide accounting, tax, or legal advice.",
  },
  {
    heading: "Database migrations and self-managed deployments",
    body: "Some Finance and shift-management features require the corresponding Supabase database migrations or schema updates. On self-managed deployments, the Merchant or administrator is responsible for applying required updates. Features may be unavailable or experience errors when required database updates have not been applied.",
  },
  {
    heading: "Camera attendance and personal information",
    body: "Where the Merchant enables photo attendance, users may be asked to provide a live photo at clock-in and clock-out. These images are used solely for store timekeeping and attendance photo verification; Synorra POS does not use facial recognition technology. The Merchant is responsible for informing staff, configuring attendance appropriately, limiting access to attendance records, and handling personal information under applicable privacy requirements, including the Philippine Data Privacy Act of 2012 (RA 10173).",
  },
  {
    heading: "Offline operation, order slips, and availability",
    body: "Synorra POS supports local offline transaction queueing. Offline operations depend on local device storage and device integrity; queued changes may remain pending until the device reconnects. The Merchant is responsible for reviewing synchronization status and reconciling records. Synorra is not responsible for loss caused by cleared browser or app data, device damage, or failure to reconnect and synchronize offline queues. Internet, power, device, printer, hosting, and third-party outages can interrupt service. The Service is provided on an as-is and as-available basis; no uptime service-level agreement or guaranteed offline synchronization is offered.",
  },
  {
    heading: "Intellectual property and limits",
    body: "The Merchant must keep any business records required by law and verify slip, tax, and regulatory settings with qualified advisers. To the extent permitted by law, Synorra and its founders and developers are not liable for BIR tax-mapping penalties, audit fines, business closures, or revenue losses caused by service interruptions, internet outages, hardware or printer failures, or cashier errors. The Merchant remains responsible for its own configuration and operations. Nothing in these Terms excludes liability that cannot legally be excluded.",
  },
  {
    heading: "Suspension and termination",
    body: "Access may be restricted to protect accounts or data, address security incidents, comply with law, or respond to a material breach. The Merchant may request account deletion through Support > Account. Before deletion, preserve any business records you are required to keep; deletion is permanent and the confirmation screen describes the data removed by the app.",
  },
  {
    heading: "Updates and contact",
    body: "These Terms are governed by the laws of the Republic of the Philippines, including the Civil Code, the E-Commerce Act (RA 8792), and the Consumer Act (RA 7394), as applicable. These Terms may be revised when the Service changes. Contact help.synorra@gmail.com with questions.",
  },
];

export const privacyPolicy: LegalSection[] = [
  {
    heading: "Information we collect",
    body: "Depending on the features used and information supplied by the Merchant, Synorra POS processes Owner and staff account details such as names, usernames, email addresses, roles, and credentials; staff profiles and HR information such as shift assignments, attendance, pay rates, and payroll calculations; live attendance photographs when photo attendance is enabled; and store operational information such as products, orders, sales, payment-method labels, cash counts, inventory, and stock changes. The current POS does not provide internal-profile fields for internal name, phone, email, physical address, loyalty accounts, or digital invoices, and it does not send digital slips.",
  },
  {
    heading: "Transaction and payment information",
    body: "The POS stores order items, totals, discounts or promotion labels, payment-method labels (Cash, GCash, or Maya), amounts paid and change, ticket numbers, timestamps, and void details. GCash and Maya are recorded as payment-method choices only; the current POS does not connect to a payment gateway or collect card numbers, CVV codes, or bank credentials. No PayMongo, Stripe, or other payment processor integration is configured in the current code. Finance features may also record shift opening floats, closing cash counts, sales totals, and cash expenses.",
  },
  {
    heading: "Staff, audit, and technical information",
    body: "Staff and Admin records may include name, username, email, role, permissions, password credentials, and Terms of Use consent metadata. The system records login/logout and shift activity, orders and void requests, inventory and restock changes, timestamps, and related staff identifiers. Where an owner enables photo attendance, the device captures and uploads a live photo with the clock-in or clock-out record for store timekeeping and photo verification. Synorra POS does not use facial recognition technology. New or changed web passwords use bcrypt; legacy records may remain in the older format until they are upgraded. Mobile offline credentials use the device secure-storage facility. The app does not request a staff phone number. The app itself does not maintain an IP-address or browser-fingerprint profile; hosting providers may collect network, device, and access logs under their own notices.",
  },
  {
    heading: "Purposes of processing",
    body: "Personal information is processed to manage user profiles and role-based access; authenticate staff and record checkout and shift attendance; calculate hours, overtime, deductions, and payroll; provide Owners with attendance verification and date-range reports; record sales, manage inventory and restocks, generate operational and finance reports, synchronize offline changes, secure accounts, and troubleshoot the Service. Attendance photographs are used solely as visual proof of staff timekeeping and are not processed for facial recognition or biometric profiling.",
  },
  {
    heading: "Sharing and service providers",
    body: "Synorra POS does not sell, trade, or rent personal information or store sales history to third parties for marketing. Store records are synchronized with the Supabase project configured for Synorra POS; the website is hosted through Vercel; and Gmail SMTP is used to send Owner password-reset emails. The app can connect to Bluetooth printers to print selected order information. Information may also be disclosed when required by a valid legal request. Confirm the providers and their data-processing terms for your deployment.",
  },
  {
    heading: "Storage and security",
    body: "Cloud operational records are stored in the Supabase project configured for the deployment, and attendance photographs are stored in a private Supabase storage bucket. The app's local offline queues and operational cache are stored on the local Android or web device until synchronization; mobile offline credentials use platform secure storage, but other operational data and pending queues are not encrypted by the app. Network security, cloud encryption, backups, and retention depend on the configured provider plans and settings and must be verified by the deployment operator. Use device locks, restrict physical access, and limit account permissions.",
  },
  {
    heading: "Retention and deletion",
    body: "The current code does not set an automatic retention schedule tied to a subscription, nor does it provide a full-store data export feature. Some reports, including attendance summaries, can be downloaded in CSV format. Account and record deletion are subject to the features currently available; Owner-account deletion permanently removes store data. Preserve records required by law before deleting data. In the Philippines, RA 11976 amended the general preservation period for books of accounts and other accounting records to five years, subject to its terms and exceptions; obtain tax advice for your business.",
  },
  {
    heading: "Camera attendance",
    body: "When a store selects an attendance mode that requires a photo, the POS captures a live image at clock-in and clock-out and stores it privately with the attendance record in the configured Supabase storage. The photo is used solely for store timekeeping and attendance photo verification. Synorra POS does not use facial recognition technology. The current code does not set an automatic attendance-photo retention schedule; the responsible business should manage access and retention in accordance with applicable requirements.",
  },
  {
    heading: "Philippine privacy framework",
    body: "Synorra respects data privacy rights under the Philippine Data Privacy Act of 2012 (Republic Act No. 10173) and its implementing rules. The Merchant is responsible for providing required notices to staff, determining and documenting an appropriate lawful basis, limiting collection and retention, securing access, and responding to data-subject requests. This policy describes product behavior and is not a certification of legal compliance. The Service operator must confirm and publish its legal entity and designated Compliance Officer for Privacy (COP) details.",
  },
  {
    heading: "Data subject rights and requests",
    body: "Under RA 10173, data subjects, including Owners, Cashiers, and Baristas, may request access to or correction of their personal information and may object to processing, subject to applicable law. Contact the Merchant or the Synorra POS developer team for privacy requests. The account owner can manage staff accounts and request Owner-account deletion in Support > Account. Deletion may be limited where records must be retained by law or are needed for legal claims. The current POS does not store internal profiles; internal requests about information collected outside the POS should be directed to the business that collected it.",
  },
  {
    heading: "Privacy contact",
    body: "For privacy inquiries or data-subject requests, contact the Synorra POS developer team at help.synorra@gmail.com. Service contact location: Zamboanga City, Philippines. The operator should confirm and publish the designated Compliance Officer for Privacy (COP) and legal entity details before treating this notice as final.",
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

export const cookieCategories = [
  {
    category: "Strictly necessary",
    purpose: "Maintains the signed-in staff session and role-based access.",
    currentUse: "synorra_session; HttpOnly; expires after 12 hours; Secure in secure production environments.",
  },
  {
    category: "Analytics",
    purpose: "Would measure site usage to improve the service.",
    currentUse: "No analytics cookies are configured by the current website code.",
  },
  {
    category: "Advertising",
    purpose: "Would support advertising or cross-site tracking.",
    currentUse: "No advertising cookies are configured by the current website code.",
  },
];
