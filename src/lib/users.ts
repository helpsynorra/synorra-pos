import type { Role, Session, StaffUser } from "@/lib/types";

export type PublicStaffUser = Omit<StaffUser, "password">;

export const DEFAULT_STAFF_PERMISSIONS = {
  stockInventory: true,
  restockInventory: true,
  connectLabels: true,
  connectReceipt: true,
  printButton: true,
  customerReceipt: true,
  cupLabels: true,
  dineIn: true,
  takeOut: true,
  promotionDiscount: false,
  promotionsEnabled: false,
} as const;

export const DEFAULT_USERS: StaffUser[] = [
  {
    id: "admin-1",
    username: "admin",
    password: "synorra",
    name: "Admin",
    role: "admin",
    title: "Admin",
  },
  {
    id: "cashier-1",
    username: "cashier",
    password: "synorra",
    name: "Sale In Charge",
    role: "cashier",
    title: "Owner",
  },
  {
    id: "barista-1",
    username: "barista",
    password: "synorra",
    name: "Barista",
    role: "barista",
    title: "Barista",
  },
];

export function staffUserId(username: string): string {
  const slug = username
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return `${slug || "user"}-${Date.now().toString(36)}`;
}

export function toSession(user: StaffUser): Session {
  return {
    userId: user.id,
    username: user.username,
    name: user.name,
    role: user.role,
    mustChangePassword: user.role === "cashier" && !user.passwordChanged,
    permissions: user.permissions ?? DEFAULT_STAFF_PERMISSIONS,
  };
}

export function publicUser(user: StaffUser): PublicStaffUser {
  return {
    id: user.id,
    username: user.username,
    email: user.email,
    passwordChanged: user.passwordChanged,
    name: user.name,
    role: user.role,
    title: user.title,
    permissions: user.permissions ?? DEFAULT_STAFF_PERMISSIONS,
  };
}

export function parseRole(value: string, fallbackRole?: string): Role {
  const normalized = String(value ?? "").trim().toLowerCase();
  const fallback = String(fallbackRole ?? "").trim().toLowerCase();
  const combined = `${normalized} ${fallback}`.trim();

  if (normalized === "pos_cashier" || fallback === "pos_cashier") return "pos_cashier";
  if (normalized === "admin" || fallback === "admin") return "admin";
  if (/admin/i.test(combined)) return "admin";
  if (normalized === "cashier" || fallback === "cashier") return "cashier";
  if (/owner|cashier|sale\s+in\s+charge/i.test(combined)) return "cashier";
  if (normalized === "barista" || fallback === "barista") return "barista";
  return "barista";
}

export function parseLoginRole(value: string): "admin" | "cashier" | null {
  const normalized = value.toLowerCase();
  if (normalized === "admin" || normalized === "cashier") {
    return normalized;
  }
  if (normalized === "owner") return "cashier";
  return null;
}

export function canUsePos(role: Role) {
  return role === "cashier";
}

export function normalizeStaffRole(item: Pick<StaffUser, "role" | "password">): Role {
  if (item.role === "admin" || item.role === "cashier" || item.role === "barista" || item.role === "pos_cashier") {
    return item.role;
  }
  return item.password ? "cashier" : "barista";
}
