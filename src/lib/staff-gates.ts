export type LoginGates = {
  admin: string;
};

export const ADMIN_LOGIN_GATE = "mouna1234";
export const OWNER_LOGIN_GATE = "back-office";

export const DEFAULT_LOGIN_GATES: LoginGates = {
  admin: ADMIN_LOGIN_GATE,
};

const RESERVED = new Set([
  "admin",
  "pos",
  "login",
  "drinks",
  "images",
  "api",
  "sale1803",
  OWNER_LOGIN_GATE,
]);

export function sanitizeLoginGate(value: string): { ok: true; value: string } | { ok: false; error: string } {
  const next = value.trim().replace(/^\/+|\/+$/g, "").toLowerCase();
  if (!next) return { ok: false, error: "Enter a login path." };
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(next)) {
    return { ok: false, error: "Use letters, numbers, and hyphens only." };
  }
  if (next.length < 4 || next.length > 32) {
    return { ok: false, error: "Keep the path between 4 and 32 characters." };
  }
  if (RESERVED.has(next)) {
    return { ok: false, error: "That path is reserved." };
  }
  return { ok: true, value: next };
}

export function normalizeLoginGates(gates?: Partial<LoginGates> | null): LoginGates {
  const adminResult = sanitizeLoginGate(gates?.admin ?? "");
  const admin = adminResult.ok ? adminResult.value : DEFAULT_LOGIN_GATES.admin;
  return { admin };
}

export function roleForLoginGate(gate: string, gates: LoginGates): "admin" | "cashier" | null {
  const value = gate.trim().replace(/^\/+|\/+$/g, "").toLowerCase();
  if (!value || value === "sale1803") return null;
  if (value === OWNER_LOGIN_GATE) return "cashier";
  if (value === gates.admin) return "admin";
  return null;
}

export function loginPathForRole(role: "admin" | "cashier", gates: LoginGates) {
  if (role === "admin") return `/${gates.admin}`;
  return `/${OWNER_LOGIN_GATE}`;
}
