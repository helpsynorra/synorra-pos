export type Role = "admin" | "cashier" | "barista" | "pos_cashier";

export type Session = {
  userId: string;
  username: string;
  name: string;
  role: Role;
  mustChangePassword?: boolean;
  permissions?: StaffPermissions;
};

export type StaffPermissions = {
  stockInventory: boolean;
  restockInventory: boolean;
  connectLabels: boolean;
  connectslip: boolean;
  printButton: boolean;
  internalslip: boolean;
  cupLabels: boolean;
  dineIn: boolean;
  takeOut: boolean;
  promotionDiscount: boolean;
  promotionsEnabled: boolean;
  wasteManagement: boolean;
  promoCodes?: PromotionCode[];
};

export type PromotionCode = {
  code: string;
  batchId?: string;
  approvalStatus?: "pending" | "approved" | "declined";
  paymentStatus?: "not_paid" | "paid";
  createdAt?: string;
  discountType: "percent" | "amount" | "item";
  discountValue: number;
  eventHost?: string;
  expiresAt?: string;
  redeemedAt?: string;
  redeemedOrderId?: string;
};

export type DrinkStyle = "iced" | "hot";

export type MenuCategoryType = string;

export type AdminLedgerKind = "expense" | "credit";

export type AdminLedgerCategory =
  | "supplies"
  | "utilities"
  | "petty_cash"
  | "restock"
  | "payroll"
  | "other";

export type LedgerPaymentSource = "cash" | "non_cash" | "unassigned";

export type AttendanceAuthMode =
  | "username_password"
  | "photo_username_password"
  | "photo_full_name_pin";

export type AdminLedgerEntry = {
  id: string;
  kind: AdminLedgerKind;
  title: string;
  reason: string;
  amount: number;
  date: string;
  category?: AdminLedgerCategory;
  status?: "unpaid" | "settled";
  counterparty?: string;
  paymentSource?: LedgerPaymentSource;
  relatedRecordId?: string;
  workShiftId?: string;
};

export type MenuAddon = {
  id: string;
  name: string;
  price: number;
  qtyEnabled?: boolean;
  inventoryItemId?: string;
  usageAmount?: number;
  usageUnit?: string;
  image?: string;
};

export type MenuTypeOption = {
  name: string;
  price: number;
};

export type OrderAddon = {
  id: string;
  name: string;
  price: number;
  qty: number;
  inventoryItemId?: string;
  usageAmount?: number;
  usageUnit?: string;
};

export type MenuItem = {
  id: string;
  name: string;
  price: number;
  category: string;
  categoryType?: MenuCategoryType;
  image: string;
  available: boolean;
  inventoryMode?: "none" | "stock_only" | "stock_and_recipe";
  stockInventoryItemId?: string;
  stockUsageAmount?: number;
  types?: (string | MenuTypeOption)[];
  styles?: DrinkStyle[];
  addons?: MenuAddon[];
};

export type OrderItem = {
  productId: string;
  name: string;
  qty: number;
  price: number;
  style?: DrinkStyle;
  category?: string;
  addons?: OrderAddon[];
  serviceMode?: "dine-in" | "take-out";
};

export type PaymentMethod = "cash" | "gcash" | "maya" | "waste" | `split:${string}`;

export type Order = {
  id: string;
  ownerId?: string;
  createdAt: string;
  baristaName: string;
  baristaUserId?: string;
  items: OrderItem[];
  total: number;
  subtotal?: number;
  discount?: number;
  promoLabel?: string;
  promoItemIndex?: number;
  promoItemQty?: number;
  paymentMethod?: PaymentMethod;
  serviceMode?: "dine-in" | "take-out";
  ticketNo?: string;
  paid?: number;
  change?: number;
  voided?: boolean;
  voidedBy?: string;
  voidedByName?: string;
  voidReason?: string;
  wasteReason?: string;
  /** Baristas recorded as in charge on waste orders; supports two or more names. */
  wasteBaristas?: string[];
  deletedAt?: string;
  recordType?: "Sale" | "Purchase" | "Waste";
};

export type PrintJobType = "cup-label" | "internal-slip";

export type PrintJobStatus = "pending" | "printed" | "failed" | "cancelled";

export type PrintJob = {
  id: string;
  orderId: string;
  type: PrintJobType;
  status: PrintJobStatus;
  attempts: number;
  createdAt: string;
  updatedAt: string;
  printedAt?: string;
  lastError?: string;
  label?: {
    productId: string;
    name: string;
    price: number;
    itemIndex: number;
    copyIndex: number;
    copiesForItem: number;
  };
};

export type PosState = {
  isOpen: boolean;
  openedAt: string | null;
  openedBy: string | null;
  inventoryFeaturesEnabled: boolean;
  printButtonHidden: boolean;
  cashDrawerOpeningFloat?: number;
  attendanceAuthMode: AttendanceAuthMode;
};

export type WorkShift = {
  id: string;
  ownerId?: string;
  name: string;
  date: string;
  startTime: string;
  endTime: string;
  openingFloat: number;
  staffUserIds: string[];
  createdAt: string;
  closingCash?: number;
  closedAt?: string;
  closedByUserId?: string;
};

export type StaffUser = {
  id: string;
  ownerId?: string;
  username: string;
  email?: string;
  password: string;
  passwordChanged?: boolean;
  agreedToTerms?: boolean;
  agreedAt?: string;
  name: string;
  role: Role;
  title: string;
  permissions?: StaffPermissions;
  hourlyRate?: number;
  dailyRate?: number;
  overtimeRate?: number;
};

export type InventoryItem = {
  id: string;
  ownerId?: string;
  name: string;
  unit: string;
  cost: number;
  stock: number;
  openingStock?: number;
  maxStock: number;
  reorderThreshold?: number;
  purchaseUnitSize?: number;
  cupUsageAmount?: number;
  cupsMake?: number;
  inventoryType?: string;
  cupSize?: string;
};

export type RecipeIngredient = {
  inventoryItemId: string;
  name: string;
  amount: number;
  unit: string;
};

export type RecipeCosting = {
  id: string;
  ownerId?: string;
  name: string;
  menuItems: string[];
  ingredients: RecipeIngredient[];
  hotCupInventoryItemId?: string;
  icedCupInventoryItemId?: string;
  otherCupInventoryItemId?: string;
  extraCupInventoryItemIds?: string[];
  /** Ingredient amounts keyed by the selected cup inventory item ID. */
  cupRecipes?: Record<string, RecipeIngredient[]>;
};

export type UsageLog = {
  id: string;
  ownerId?: string;
  orderId: string;
  orderItemId: string;
  inventoryItemId?: string;
  date: string;
  itemName: string;
  usedAmount: number;
  unit: string;
  remaining?: number;
};

export type RestockRecord = {
  id: string;
  ownerId?: string;
  inventoryItemId?: string;
  itemName: string;
  quantityAdded: number;
  // Purchase-facing snapshot of what the admin entered (e.g. 10 pcs) while
  // quantityAdded stays in normalized base units (e.g. 10000 ml). Nullable -
  // legacy rows predate these fields (KAN-126).
  purchaseQty?: number;
  purchaseUnit?: string;
  unitCost?: number;
  date: string;
};

export type PayrollRecord = {
  id: string;
  userId: string;
  staffName: string;
  periodStart: string;
  periodEnd: string;
  hours: number;
  grossPay: number;
  cashAdvance: number;
  tardinessDeduction: number;
  netPay: number;
  status: "unpaid" | "paid";
  payoutLedgerId?: string;
  paidAt?: string;
};

export type LoginActivity = {
  id: string;
  ownerId?: string;
  userId: string;
  username: string;
  name: string;
  role: Role;
  type: "login" | "logout";
  at: string;
  photoPath?: string;
};

export type OffRequest = {
  id: string;
  ownerId?: string;
  userId: string;
  name: string;
  date: string;
  reason: string;
  status: "pending" | "approved" | "denied";
  createdAt: string;
};

export type VoidRequest = {
  id: string;
  ownerId?: string;
  requestedAt: string;
  requestedById: string;
  requestedByName: string;
  reason: string;
  status: "pending" | "approved";
  orderId?: string;
  items: OrderItem[];
  subtotal: number;
  discount: number;
  promoLabel?: string;
  total: number;
  paymentMethod: PaymentMethod;
  approvedAt?: string;
  approvedByName?: string;
  processedOrderId?: string;
};

export type StoreData = {
  pos: PosState;
  orders: Order[];
  printJobs: PrintJob[];
  menu: MenuItem[];
  categories: string[];
  categoryTypes?: Record<string, MenuCategoryType>;
  users: StaffUser[];
  inventory: InventoryItem[];
  recipes: Record<string, RecipeIngredient[]>;
  recipeCostings: RecipeCosting[];
  usageLogs: UsageLog[];
  restocks: RestockRecord[];
  loginActivity: LoginActivity[];
  workShifts: WorkShift[];
  workShiftError?: string;
  offRequests: OffRequest[];
  voidRequests: VoidRequest[];
  loginGates: {
    admin: string;
  };
};
