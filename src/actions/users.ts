"use server";

import bcrypt from "bcryptjs";
import { cookies } from "next/headers";
import { revalidatePath } from "next/cache";
import { randomUUID } from "node:crypto";
import {
  SESSION_COOKIE,
  encodeSession,
  getSession,
  sessionCookieOptions,
} from "@/lib/auth";
import {
  deleteOwnerAccountAndData,
  deleteLoginActivityRecords,
  deleteOffRequestRecord,
  deleteOwnerPromotionRecord,
  deleteCommunePromotionRecord,
  endCommunePromotionEventRecord,
  deleteStaffUserRecord,
  getFreshStore,
  getOwnerAccounts,
  getCommunePromotionRecords,
  createCommunePromotionBatchRecord,
  setCommunePromotionBatchPaymentStatus,
  getStore,
  initializeOwnerStore,
  insertOwnerPromotionRecord,
  insertCommunePromotionRecord,
  markCommunePromotionBatchReady,
  isRealSupabaseConfigured,
  insertLoginActivityRecord,
  insertOffRequestRecord,
  updateLoginActivityTimeRecord,
  updateOffRequestStatusRecord,
  updateStore,
  upsertStaffUserRecord,
} from "@/lib/store";
import { phDateString, phIsoFromDateTimeInput } from "@/lib/datetime";
import { isAttendanceStaffRole, openBaristaShifts, pairLoginSessions } from "@/lib/staff-sessions";
import {
  canUsePos,
  parseRole,
  staffUserId,
  toSession,
} from "@/lib/users";
import { sanitizeLoginGate } from "@/lib/staff-gates";
import type { LoginActivity, OffRequest, Order, PromotionCode, Role, StaffPermissions, StaffUser, StoreData } from "@/lib/types";

async function requireAdmin() {
  const session = await getSession();
  if (!session || session.role !== "admin") {
    throw new Error("Only admin can manage staff.");
  }
  return session;
}

function refresh() {
  revalidatePath("/synorra-host");
  revalidatePath("/owner");
  revalidatePath("/pos");
}

async function requirePosSession() {
  const session = await getSession();
  if (!session || !canUsePos(session.role)) {
    throw new Error("Only an active Owner POS session can open the barista shift module.");
  }
  return session;
}

function compactStaffKey(value: string) {
  return String(value ?? "").trim().toLowerCase().replace(/[^a-z0-9]/g, "");
}

function hasBaristaCredentials(user: StaffUser, username: string, password: string) {
  const normalizedUsername = username.trim().toLowerCase();
  const normalizedPassword = password.trim();
  const passwordMatches = user.password.startsWith("$2")
    ? bcrypt.compareSync(normalizedPassword, user.password)
    : user.password.trim() === normalizedPassword;
  return (user.role === "barista" || user.role === "pos_cashier") &&
    user.password.trim().length > 0 &&
    passwordMatches &&
    (user.username.trim().toLowerCase() === normalizedUsername ||
      compactStaffKey(user.username) === compactStaffKey(normalizedUsername) ||
      compactStaffKey(user.name) === compactStaffKey(normalizedUsername));
}

// Still mutates store.loginActivity in memory synchronously (so an
// "already clocked in" check made later in the same updateStore() queue
// turn sees this punch immediately, exactly as before persistence was
// added) - it returns the created entry so the caller can persist it via
// insertLoginActivityRecord() once this queue turn has finished, rather
// than nesting a DB call inside updateStore()'s callback.
function appendPunch(store: StoreData, user: StaffUser, type: "login" | "logout", role = user.role): LoginActivity {
  if (!Array.isArray(store.loginActivity)) store.loginActivity = [];
  const activity: LoginActivity = {
    id: `auth-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`,
    userId: user.id,
    username: user.username,
    name: user.name,
    role,
    type,
    at: new Date().toISOString(),
  };
  store.loginActivity.unshift(activity);
  return activity;
}

function parseStaff(input: {
  name: string;
  username: string;
  email: string;
  title: string;
  role: string;
  password: string;
  hourlyRate: string;
  dailyRate: string;
  overtimeRate: string;
  requirePassword: boolean;
}): { error: string } | { name: string; username: string; email: string; title: string; role: Role; password?: string; hourlyRate?: number; dailyRate?: number; overtimeRate: number } {
  const name = input.name.trim();
  const role = parseRole(input.role);
  if (!name) return { error: "Enter a display name." };

  const title =
    role === "barista" || role === "pos_cashier"
      ? (input.title.trim() || "Barista")
      : role === "cashier"
        ? "Owner"
        : "Admin";
  const password = input.password;
  const email = input.email.trim().toLowerCase();
  const hourlyRate = input.hourlyRate.trim() ? Number(input.hourlyRate) : undefined;
  const dailyRate = input.dailyRate.trim() ? Number(input.dailyRate) : undefined;
  const overtimeRate = input.overtimeRate.trim() ? Number(input.overtimeRate) : 1.5;
  const username = (
    input.username.trim() ||
    name.toLowerCase().replace(/[^a-z0-9]+/g, "")
  )
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "")
    .slice(0, 32);

  if (!username || username.length < 2) {
    return { error: "Enter a username (letters and numbers)." };
  }
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return { error: "Enter a valid email address." };
  }
  if (input.requirePassword && password.length < 4) {
    return { error: "Password must be at least 4 characters." };
  }
  if (
    (hourlyRate !== undefined && (!Number.isFinite(hourlyRate) || hourlyRate < 0)) ||
    (dailyRate !== undefined && (!Number.isFinite(dailyRate) || dailyRate < 0)) ||
    !Number.isFinite(overtimeRate) ||
    overtimeRate < 1 ||
    (hourlyRate !== undefined && dailyRate !== undefined && hourlyRate > 0 && dailyRate > 0)
  ) {
    return { error: "Enter one valid hourly or daily rate and an overtime multiplier of at least 1." };
  }
  if (!input.requirePassword && password && password.length < 4) {
    return { error: "Password must be at least 4 characters." };
  }

  return {
    name,
    username,
    email,
    title,
    role,
    password: password ? password : undefined,
    hourlyRate: hourlyRate || undefined,
    dailyRate: dailyRate || undefined,
    overtimeRate,
  };
}

export async function createStaffUser(input: {
  name: string;
  username: string;
  email: string;
  title: string;
  role: string;
  password: string;
  hourlyRate: string;
  dailyRate: string;
  overtimeRate: string;
}) {
  const session = await getSession();
  if (!session || (session.role !== "admin" && session.role !== "cashier")) {
    throw new Error("Only an Owner or admin can manage staff.");
  }
  const parsed = parseStaff({ ...input, requirePassword: true });
  if ("error" in parsed) return parsed;
  if (session.role === "cashier" && parsed.role !== "barista" && parsed.role !== "pos_cashier") {
    return { error: "Owners can only create staff accounts." };
  }

  const store = session.role === "admin" && parsed.role === "cashier"
    ? { users: await getOwnerAccounts() }
    : await getFreshStore();
  const taken = (store.users ?? []).some(
    (user) => user.username.trim().toLowerCase() === parsed.username.toLowerCase(),
  );
  if (taken) {
    return { error: "That username is already in use." };
  }
  if (parsed.email && (store.users ?? []).some((user) => user.email?.trim().toLowerCase() === parsed.email)) {
    return { error: "That email is already assigned to a staff account." };
  }

  try {
    const id = parsed.role === "cashier"
      ? staffUserId(parsed.username)
      : session.role === "cashier"
        ? `${session.userId}--${staffUserId(parsed.username)}`
        : staffUserId(parsed.username);
    await upsertStaffUserRecord({
      id,
      name: parsed.name,
      username: parsed.username,
      email: parsed.email,
      title: parsed.title,
      role: parsed.role,
      password: parsed.password ?? "",
      passwordChanged: false,
      ownerId: parsed.role === "cashier" ? id : session.role === "cashier" ? session.userId : undefined,
      hourlyRate: parsed.hourlyRate,
      dailyRate: parsed.dailyRate,
      overtimeRate: parsed.overtimeRate,
    });
    if (parsed.role === "cashier") {
      await initializeOwnerStore(id);
    }
  } catch (err) {
    return { error: err instanceof Error ? err.message : "Could not create staff account." };
  }

  refresh();
  return { ok: true };
}

export async function updateStaffUser(input: {
  id: string;
  name: string;
  username: string;
  email: string;
  title: string;
  role: string;
  password: string;
  hourlyRate: string;
  dailyRate: string;
  overtimeRate: string;
}) {
    const session = await getSession();
  if (!session || (session.role !== "admin" && session.role !== "cashier")) {
    return { error: "Only an Owner or admin can edit staff accounts." };
  }
  const isOwner = session.role === "cashier";
  const parsed = parseStaff({ ...input, requirePassword: false });
  if ("error" in parsed) return parsed;
  if (isOwner && !isAttendanceStaffRole(parsed.role)) {
    return { error: "Owners can only edit Barista or Cashier accounts." };
  }

  const store = await getFreshStore({ ownerId: isOwner ? session.userId : null });
  const user = (store.users ?? []).find((entry) => entry.id === input.id);
  if (
    !user ||
    (isOwner &&
      (!isAttendanceStaffRole(user.role) ||
        (user.ownerId && user.ownerId !== session.userId)))
  ) {
    return { error: "Staff account not found." };
  }
  const taken = (store.users ?? []).some(
    (entry) => entry.id !== input.id && entry.username.trim().toLowerCase() === parsed.username.toLowerCase(),
  );
  if (taken) {
    return { error: "That username is already in use." };
  }
  if (parsed.email && (store.users ?? []).some((entry) => entry.id !== input.id && entry.email?.trim().toLowerCase() === parsed.email)) {
    return { error: "That email is already assigned to a staff account." };
  }
  const admins = (store.users ?? []).filter((entry) => entry.role === "admin");
  if (
    !isOwner &&
    user.role === "admin" &&
    parsed.role !== "admin" &&
    admins.length < 2
  ) {
    return { error: "Keep at least one admin account." };
  }

  const nextUser: StaffUser = {
    ...user,
    name: parsed.name,
    username: parsed.username,
    email: parsed.email,
    title: parsed.title,
    role: parsed.role,
    password: parsed.password ? parsed.password : user.password,
    passwordChanged: parsed.password ? false : user.passwordChanged,
    hourlyRate: parsed.hourlyRate,
    dailyRate: parsed.dailyRate,
    overtimeRate: parsed.overtimeRate,
  };

  try {
    await upsertStaffUserRecord(nextUser);
  } catch (err) {
    return { error: err instanceof Error ? err.message : "Could not update staff account." };
  }

  if (session.userId === nextUser.id) {
    const jar = await cookies();
    jar.set(SESSION_COOKIE, encodeSession(toSession(nextUser)), sessionCookieOptions());
  }

  refresh();
  return { ok: true };
}

export async function updateStaffPassword(userId: string, password: string) {
  const session = await getSession();
  if (!session || session.role !== "cashier") {
    throw new Error("Only the Owner can change staff passwords.");
  }
  const nextPassword = String(password ?? "").trim();
  if (nextPassword.length < 4 || nextPassword.length > 128) {
    return { error: "Password must be between 4 and 128 characters." };
  }

  const store = await getFreshStore({ ownerId: session.userId });
  const user = store.users.find((entry) => entry.id === userId);
  if (!user || (user.role !== "barista" && user.role !== "pos_cashier") || (user.ownerId && user.ownerId !== session.userId)) {
    return { error: "Staff account not found in your workspace." };
  }

  try {
    await upsertStaffUserRecord({
      ...user,
      password: await bcrypt.hash(nextPassword, 12),
      passwordChanged: true,
    });
  } catch (error) {
    return { error: error instanceof Error ? error.message : "Could not change staff password." };
  }

  refresh();
  return { ok: true };
}

export async function updateOwnerPermissions(userId: string, permissions: StaffPermissions) {
  await requireAdmin();
  const store = await getFreshStore({ ownerId: userId });
  const user = store.users.find((entry) => entry.id === userId);
  if (!user || user.role !== "cashier") return { error: "Owner account not found." };

  const normalized: StaffPermissions = {
    stockInventory: permissions.stockInventory === true,
    restockInventory: permissions.restockInventory === true,
    connectLabels: permissions.connectLabels === true,
    connectslip: permissions.connectslip === true,
    printButton: permissions.printButton === true,
    internalslip: permissions.internalslip === true,
    cupLabels: permissions.cupLabels === true,
    dineIn: permissions.dineIn === true,
    takeOut: permissions.takeOut === true,
    promotionDiscount: permissions.promotionDiscount === true,
    promotionsEnabled: permissions.promotionsEnabled === true,
    wasteManagement: permissions.wasteManagement === true,
    promoCodes: user.permissions?.promoCodes ?? [],
  };
  // Supabase stores promotion records separately, while the in-memory store
  // keeps them on the Owner permission object. Preserve them in both cases.
  try {
    await upsertStaffUserRecord({ ...user, permissions: normalized });
  } catch (error) {
    return { error: error instanceof Error ? error.message : "Could not save Owner permissions." };
  }
  refresh();
  return { ok: true };
}

export async function generateOwnerPromotionCode(
  userId: string,
  discountType: "percent" | "amount" | "item",
  discountValue: number,
  count = 1,
  prefix = "SYNORRA",
  expiresOn = "",
) {
  await requireAdmin();
  if (discountType !== "percent" && discountType !== "amount" && discountType !== "item") {
    return { error: "Choose a valid promotion discount type." };
  }
  const store = await getFreshStore({ ownerId: userId });
  const owner = store.users.find((entry) => entry.id === userId && entry.role === "cashier");
  if (!owner) return { error: "Owner account not found." };
  if (owner.permissions?.promotionsEnabled !== true) return { error: "Enable promotions for this Owner first." };
  const codeCount = Number(count);
  if (!Number.isInteger(codeCount) || codeCount < 1 || codeCount > 100) {
    return { error: "Choose between 1 and 100 promotion codes." };
  }
  const normalizedPrefix = prefix.trim().toUpperCase();
  if (!/^[A-Z0-9]{1,16}$/.test(normalizedPrefix)) {
    return { error: "Enter a code prefix with 1 to 16 letters or numbers." };
  }
  const expiryDay = new Date(`${expiresOn}T00:00:00.000Z`);
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(expiresOn) ||
    Number.isNaN(expiryDay.getTime()) ||
    expiryDay.toISOString().slice(0, 10) !== expiresOn ||
    expiresOn < phDateString()
  ) {
    return { error: "Choose a valid expiration date that is today or later." };
  }
  const expiresAt = new Date(`${expiresOn}T23:59:59.999+08:00`).toISOString();
  const value = Number(discountValue);
  if (discountType === "item" && (!Number.isInteger(value) || value < 1 || value > 99)) {
    return { error: "Choose between 1 and 99 free items." };
  }
  if (discountType !== "item" && (!Number.isFinite(value) || value <= 0 || (discountType === "percent" && value > 100))) {
    return { error: "Enter a valid promotion discount." };
  }
  const promos: Awaited<ReturnType<typeof insertOwnerPromotionRecord>>[] = [];
  try {
    for (let index = 0; index < codeCount; index += 1) {
      promos.push(await insertOwnerPromotionRecord(
        userId,
        { discountType, discountValue: Math.round(value * 100) / 100, expiresAt },
        normalizedPrefix,
      ));
    }
    refresh();
    return { ok: true, promo: promos[0], promos };
  } catch (error) {
    refresh();
    return {
      error: error instanceof Error ? error.message : "Could not generate a promotion code.",
      promos,
    };
  }
}

export async function deleteOwnerPromotionCode(userId: string, code: string) {
  await requireAdmin();
  const normalizedCode = code.trim().toUpperCase();
  if (!/^(?:[A-Z0-9]{6}|[A-Z0-9]{1,16}-[A-Z0-9]{6})$/.test(normalizedCode)) return { error: "Invalid promotion code." };
  const store = await getFreshStore({ ownerId: userId });
  const owner = store.users.find((entry) => entry.id === userId && entry.role === "cashier");
  if (!owner) return { error: "Owner account not found." };
  try {
    await deleteOwnerPromotionRecord(userId, normalizedCode);
    refresh();
    return { ok: true };
  } catch (error) {
    return { error: error instanceof Error ? error.message : "Could not delete promotion code." };
  }
}

export async function getCommunePromotionCodes() {
  await requireAdmin();
  try {
    return { promos: await getCommunePromotionRecords() };
  } catch (error) {
    return { error: error instanceof Error ? error.message : "Could not load Commune vouchers." };
  }
}

export async function generateCommunePromotionCodes(
  discountType: "percent" | "amount" | "item",
  discountValue: number,
  count: number,
  prefix: string,
  eventHost: string,
  expiresOn: string,
) {
  await requireAdmin();
  if (discountType !== "percent" && discountType !== "amount" && discountType !== "item") {
    return { error: "Choose a valid promotion discount type." };
  }
  const codeCount = Number(count);
  if (!Number.isInteger(codeCount) || codeCount < 1 || codeCount > 100) {
    return { error: "Choose between 1 and 100 Commune voucher codes." };
  }
  const normalizedPrefix = prefix.trim().toUpperCase();
  if (!/^[A-Z0-9]{1,16}$/.test(normalizedPrefix)) {
    return { error: "Enter a prefix with 1 to 16 letters or numbers." };
  }
  const normalizedEventHost = eventHost.trim();
  if (normalizedEventHost.length > 120) {
    return { error: "Event Host must be 120 characters or fewer." };
  }
  const expiryDay = new Date(`${expiresOn}T00:00:00.000Z`);
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(expiresOn) ||
    Number.isNaN(expiryDay.getTime()) ||
    expiryDay.toISOString().slice(0, 10) !== expiresOn ||
    expiresOn < phDateString()
  ) {
    return { error: "Choose a valid expiration date that is today or later." };
  }
  const value = Number(discountValue);
  if (discountType === "item" && (!Number.isInteger(value) || value < 1 || value > 99)) {
    return { error: "Choose between 1 and 99 free items." };
  }
  if (discountType !== "item" && (!Number.isFinite(value) || value <= 0 || (discountType === "percent" && value > 100))) {
    return { error: "Enter a valid promotion discount." };
  }

  const expiresAt = new Date(`${expiresOn}T23:59:59.999+08:00`).toISOString();
  const batchId = randomUUID();
  const promos: PromotionCode[] = [];
  try {
    await createCommunePromotionBatchRecord(batchId, {
      discountType,
      discountValue: Math.round(value * 100) / 100,
      eventHost: normalizedEventHost,
      expiresAt,
    }, codeCount);
    for (let index = 0; index < codeCount; index += 1) {
      promos.push(await insertCommunePromotionRecord({
        discountType,
        discountValue: Math.round(value * 100) / 100,
        eventHost: normalizedEventHost,
        expiresAt,
      }, normalizedPrefix, batchId));
    }
    await markCommunePromotionBatchReady(batchId);
    refresh();
    return { ok: true, promos };
  } catch (error) {
    try { await markCommunePromotionBatchReady(batchId); } catch { /* Keep the original generation error. */ }
    refresh();
    return {
      error: error instanceof Error ? error.message : "Could not generate Commune vouchers.",
      promos,
    };
  }
}

export async function updateCommunePromotionBatchPaymentStatus(
  batchId: string,
  paymentStatus: "not_paid" | "paid",
) {
  await requireAdmin();
  const normalizedBatchId = batchId.trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(normalizedBatchId)) {
    return { error: "Invalid Commune voucher batch." };
  }
  if (paymentStatus !== "not_paid" && paymentStatus !== "paid") {
    return { error: "Choose Not Paid or Paid." };
  }
  try {
    await setCommunePromotionBatchPaymentStatus(normalizedBatchId, paymentStatus);
    refresh();
    return { ok: true as const, batchId: normalizedBatchId, paymentStatus };
  } catch (error) {
    return { error: error instanceof Error ? error.message : "Could not update the payment status." };
  }
}

export async function endCommunePromotionEvent(eventHost: string) {
  await requireAdmin();
  const normalizedHost = eventHost.trim();
  if (!normalizedHost || normalizedHost.length > 120) return { ok: false as const, error: "Enter a valid event host." };
  try {
    const result = await endCommunePromotionEventRecord(normalizedHost);
    refresh();
    return { ok: true as const, ...result };
  } catch (error) {
    return { ok: false as const, error: error instanceof Error ? error.message : "Could not end the Commune promotion event." };
  }
}

export async function getCommunePromotionDiscountSummary(): Promise<
  | { totalDiscountGiven: number; orders: Pick<Order, "id" | "ticketNo" | "promoLabel" | "discount" | "createdAt" | "items">[] }
  | { error: string }
> {
  await requireAdmin();
  const secret = process.env.COMMUNE_PROMOTION_SHARED_SECRET?.trim();
  if (!secret) return { error: "Commune promotion integration is not configured." };
  const reportUrl = process.env.COMMUNE_PROMOTION_REPORT_URL?.trim() ||
    "https://commune-staging.vercel.app/api/synorra-promo-summary";
  try {
    const response = await fetch(reportUrl, {
      headers: { "x-commune-promotion-secret": secret },
      cache: "no-store",
      signal: AbortSignal.timeout(8000),
    });
    const responseText = await response.text();
    let payload: Record<string, unknown>;
    try {
      payload = JSON.parse(responseText) as Record<string, unknown>;
    } catch {
      return { error: `Commune report endpoint returned a non-JSON response (HTTP ${response.status}). Deploy /api/synorra-promo-summary on Commune and check COMMUNE_PROMOTION_REPORT_URL.` };
    }
    const totalDiscountGiven = Number(payload.totalDiscountGiven);
    if (!response.ok || !Number.isFinite(totalDiscountGiven) || !Array.isArray(payload.orders)) {
      return { error: typeof payload.error === "string" ? payload.error : "Could not load Commune's promo discount total." };
    }
    return {
      totalDiscountGiven,
      orders: payload.orders as Pick<Order, "id" | "ticketNo" | "promoLabel" | "discount" | "createdAt" | "items">[],
    };
  } catch (error) {
    return { error: error instanceof Error ? error.message : "Could not load Commune's promo discount total." };
  }
}

export async function deleteCommunePromotionCode(code: string) {
  await requireAdmin();
  const normalizedCode = code.trim().toUpperCase();
  if (!/^[A-Z0-9]{1,16}-[A-Z0-9]{6}$/.test(normalizedCode)) return { error: "Invalid Commune voucher code." };
  try {
    await deleteCommunePromotionRecord(normalizedCode);
    refresh();
    return { ok: true };
  } catch (error) {
    return { error: error instanceof Error ? error.message : "Could not delete Commune voucher." };
  }
}

export async function deleteStaffUser(id: string) {
  const session = await getSession();
  if (!session || (session.role !== "admin" && session.role !== "cashier")) {
    throw new Error("Only an Owner or admin can manage staff.");
  }
  if (session.userId === id) {
    return { error: "You cannot delete the account you are using." };
  }

  if (session.role === "admin" && isRealSupabaseConfigured()) {
    const owner = (await getOwnerAccounts()).find((entry) => entry.id === id);
    if (!owner) return { error: "Owner account not found." };

    try {
      await deleteOwnerAccountAndData(owner.id);
    } catch (error) {
      return {
        error:
          error instanceof Error
            ? error.message
            : "Could not delete that Owner account and its store data.",
      };
    }
    refresh();
    return { ok: true };
  }

  const store = await getStore();
  const user = store.users.find((entry) => entry.id === id);
  if (!user) {
    return { error: "Staff account not found." };
  }
  if (session.role === "cashier" && user.role !== "barista" && user.role !== "pos_cashier") {
    return { error: "Owners can only delete staff accounts." };
  }
  const admins = store.users.filter((entry) => entry.role === "admin");
  if (user.role === "admin" && admins.length < 2) {
    return { error: "Keep at least one admin account." };
  }

  try {
    await deleteStaffUserRecord(id);
  } catch (error) {
    return { error: error instanceof Error ? error.message : "Could not delete that staff account." };
  }
  refresh();
  return { ok: true };
}

export async function punchStaff(userId: string, type: "login" | "logout") {
  await requireAdmin();
  let error: string | undefined;
  let activity: LoginActivity | undefined;
  await updateStore((store) => {
    const user = store.users.find((entry) => entry.id === userId);
    if (!user || !isAttendanceStaffRole(user.role)) {
      error = "Pick a staff member.";
      return;
    }
    const isOnShift = pairLoginSessions(store.loginActivity ?? []).some(
      (shift) => shift.userId === userId && !shift.logoutAt,
    );
    if (type === "login" && isOnShift) {
      error = `${user.name} is already clocked in.`;
      return;
    }
    if (type === "logout" && !isOnShift) {
      error = `${user.name} does not have an open shift.`;
      return;
    }
    activity = appendPunch(store, user, type);
  });
  if (error) return { error };
  if (activity) await insertLoginActivityRecord(activity);
  refresh();
  return { ok: true };
}

export async function punchBaristaShift(input: {
  type: "login" | "logout";
  username?: string;
  password?: string;
  userId?: string;
}) {
  await requirePosSession();

  let error: string | undefined;
  let punched: { id: string; name: string; username: string } | undefined;
  let activity: LoginActivity | undefined;
  await updateStore((store) => {
    const openShifts = openBaristaShifts(store.loginActivity ?? []);

    if (input.type === "login") {
      const username = String(input.username ?? "").trim().toLowerCase();
      const compact = compactStaffKey(username);
      const password = String(input.password ?? "").trim();
      const user = store.users.find((entry) => {
        const entryUser = String(entry.username ?? "").trim().toLowerCase();
        return (
          entryUser === username ||
          compactStaffKey(entry.username) === compact ||
          compactStaffKey(entry.name) === compact
        );
      });
      if (!user || !hasBaristaCredentials(user, username, password)) {
        error = "Use a staff account to clock in here.";
        return;
      }
      if (openShifts.some((shift) => shift.userId === user.id)) {
        punched = { id: user.id, name: user.name, username: user.username };
        error = `${user.name} is already clocked in.`;
        return;
      }
      activity = appendPunch(store, user, "login");
      punched = { id: user.id, name: user.name, username: user.username };
      return;
    }

    const userId = String(input.userId ?? "").trim();
    const open = openShifts.find((shift) => shift.userId === userId) ?? (userId ? null : openShifts[0]);
    if (!open) {
      error = "That staff member is not clocked in.";
      return;
    }
    const user = store.users.find((entry) => entry.id === open.userId);
    if (!user) {
      error = "Staff account not found.";
      return;
    }
    if (!hasBaristaCredentials(user, input.username ?? "", input.password ?? "")) {
      error = "Use the on-shift staff member's own username and password to clock out.";
      return;
    }
    activity = appendPunch(store, user, "logout");
    punched = { id: user.id, name: user.name, username: user.username };
  });

  if (error) {
    return punched
      ? { error, id: punched.id, name: punched.name, username: punched.username }
      : { error };
  }
  if (activity) await insertLoginActivityRecord(activity);
  refresh();
  return { ok: true as const, id: punched?.id ?? "", name: punched?.name ?? "", username: punched?.username ?? "" };
}

export async function updateStaffSessionTimes(input: {
  loginId?: string;
  loginAt?: string;
  logoutId?: string;
  logoutAt?: string;
}) {
  await requireAdmin();

  if (!input.loginId && !input.logoutId) {
    return { error: "No in / out time was selected." };
  }

  const loginAt = input.loginId ? phIsoFromDateTimeInput(input.loginAt ?? "") : undefined;
  const logoutAt = input.logoutId ? phIsoFromDateTimeInput(input.logoutAt ?? "") : undefined;
  if ((input.loginId && !loginAt) || (input.logoutId && !logoutAt)) {
    return { error: "Enter a valid date and time." };
  }

  const store = await getStore();
  const login = input.loginId
    ? store.loginActivity.find((entry) => entry.id === input.loginId && entry.type === "login")
    : undefined;
  const logout = input.logoutId
    ? store.loginActivity.find((entry) => entry.id === input.logoutId && entry.type === "logout")
    : undefined;

  if ((input.loginId && !login) || (input.logoutId && !logout)) {
    return { error: "In / off record not found." };
  }
  if (login && logout && login.userId !== logout.userId) {
    return { error: "The in and off records do not belong to the same staff member." };
  }

  const nextLoginAt = loginAt ?? login?.at;
  const nextLogoutAt = logoutAt ?? logout?.at;
  if (
    nextLoginAt &&
    nextLogoutAt &&
    new Date(nextLogoutAt).getTime() < new Date(nextLoginAt).getTime()
  ) {
    return { error: "Off time cannot be earlier than in time." };
  }

  // Targeted single-row updates, not a rebuild of the whole activity array.
  if (login && loginAt) await updateLoginActivityTimeRecord(login.id, loginAt);
  if (logout && logoutAt) await updateLoginActivityTimeRecord(logout.id, logoutAt);

  refresh();
  return { ok: true };
}

export async function deleteStaffSession(input: { loginId?: string; logoutId?: string }) {
  const session = await getSession();
  if (!session || (session.role !== "admin" && session.role !== "cashier")) {
    return { error: "Only an Owner or admin can delete staff in / out records." };
  }

  if (!input.loginId && !input.logoutId) {
    return { error: "No in / out record was selected." };
  }

  const ids = [input.loginId, input.logoutId].filter((id): id is string => Boolean(id));
  const store = await getFreshStore();
  const records = ids.map((id) => store.loginActivity.find((entry) => entry.id === id));
  if (records.some((record) => !record)) {
    return { error: "In / out record not found." };
  }
  const selectedRecords = records.filter((record): record is LoginActivity => Boolean(record));
  if (
    (input.loginId && selectedRecords.find((record) => record.id === input.loginId)?.type !== "login") ||
    (input.logoutId && selectedRecords.find((record) => record.id === input.logoutId)?.type !== "logout")
  ) {
    return { error: "Select valid in and off records." };
  }
  if (new Set(selectedRecords.map((record) => record.userId)).size !== 1) {
    return { error: "The in and off records do not belong to the same staff member." };
  }
  if (
    session.role === "cashier" &&
    selectedRecords.some((record) => !isAttendanceStaffRole(record.role))
  ) {
    return { error: "Owners can only delete Cashier or Barista in / out records." };
  }

  // Delete exactly the rows this session is made of (its loginId and/or
  // logoutId), not the whole array - other sessions/users are untouched.
  await deleteLoginActivityRecords(ids);

  refresh();
  return { ok: true };
}

export async function createOffRequest(input: { userId?: string; date: string; reason: string }) {
  const session = await getSession();
  if (!session) return { error: "Sign in first." };
  const date = phDateString(input.date);
  const reason = input.reason.trim();
  if (!date) return { error: "Pick a date." };
  if (!reason) return { error: "Enter a reason." };

  const asAdmin = session.role === "admin";
  if (!asAdmin && session.role !== "cashier") {
    return { error: "Only staff can request off." };
  }

  const store = await getStore();
  const userId = asAdmin ? input.userId : session.userId;
  const user = store.users.find((entry) => entry.id === userId);
  if (!user || user.role === "admin") {
    return { error: "Pick a staff member." };
  }

  await insertOffRequestRecord({
    id: `off-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`,
    userId: user.id,
    name: user.name,
    date,
    reason,
    status: asAdmin ? "approved" : "pending",
    createdAt: new Date().toISOString(),
  });
  refresh();
  return { ok: true };
}

export async function setOffRequestStatus(id: string, status: OffRequest["status"]) {
  await requireAdmin();
  const store = await getStore();
  const request = store.offRequests?.find((entry) => entry.id === id);
  if (!request) {
    return { error: "Request not found." };
  }
  await updateOffRequestStatusRecord(id, status);
  refresh();
  return { ok: true };
}

export async function deleteOffRequest(id: string) {
  await requireAdmin();
  await deleteOffRequestRecord(id);
  refresh();
  return { ok: true };
}

export async function updateLoginGates(
  adminPath: string,
): Promise<{ error: string } | { ok: true; admin: string }> {
  await requireAdmin();
  const admin = sanitizeLoginGate(adminPath);
  if (!admin.ok) return { error: admin.error };

  let previousAdmin = "";
  await updateStore((store) => {
    previousAdmin = store.loginGates.admin;
    store.loginGates = { admin: admin.value };
  });
  refresh();
  if (previousAdmin) revalidatePath(`/${previousAdmin}`);
  revalidatePath(`/${admin.value}`);
  return { ok: true, admin: admin.value };
}
