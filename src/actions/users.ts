"use server";

import bcrypt from "bcryptjs";
import { cookies } from "next/headers";
import { revalidatePath } from "next/cache";
import {
  SESSION_COOKIE,
  encodeSession,
  getSession,
  sessionCookieOptions,
} from "@/lib/auth";
import {
  deleteLoginActivityRecords,
  deleteOffRequestRecord,
  deleteStaffUserRecord,
  getFreshStore,
  getStore,
  insertLoginActivityRecord,
  insertOffRequestRecord,
  updateLoginActivityTimeRecord,
  updateOffRequestStatusRecord,
  updateStore,
  upsertStaffUserRecord,
} from "@/lib/store";
import { phDateString, phIsoFromDateTimeInput } from "@/lib/datetime";
import { openBaristaShifts, pairLoginSessions } from "@/lib/staff-sessions";
import {
  canUsePos,
  DEFAULT_STAFF_PERMISSIONS,
  parseRole,
  staffUserId,
  toSession,
} from "@/lib/users";
import { sanitizeLoginGate } from "@/lib/staff-gates";
import type { LoginActivity, OffRequest, Role, StaffPermissions, StaffUser, StoreData } from "@/lib/types";

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
  return user.role === "barista" &&
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
  requirePassword: boolean;
}): { error: string } | { name: string; username: string; email: string; title: string; role: Role; password?: string } {
  const name = input.name.trim();
  const role = parseRole(input.role);
  if (!name) return { error: "Enter a display name." };

  const title =
    role === "barista"
      ? (input.title.trim() || "Barista")
      : role === "cashier"
        ? "Owner"
        : "Admin";
  const password = input.password;
  const email = input.email.trim().toLowerCase();
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
  };
}

export async function createStaffUser(input: {
  name: string;
  username: string;
  email: string;
  title: string;
  role: string;
  password: string;
}) {
  const session = await getSession();
  if (!session || (session.role !== "admin" && session.role !== "cashier")) {
    throw new Error("Only an Owner or admin can manage staff.");
  }
  const parsed = parseStaff({ ...input, requirePassword: true });
  if ("error" in parsed) return parsed;
  if (session.role === "cashier" && parsed.role !== "barista") {
    return { error: "Owners can only create Barista accounts." };
  }

  const store = await getFreshStore();
  const taken = (store.users ?? []).some(
    (user) => user.username.trim().toLowerCase() === parsed.username.toLowerCase(),
  );
  if (taken) {
    return { error: "That username is already in use." };
  }
  if (parsed.email && (store.users ?? []).some((user) => user.email?.toLowerCase() === parsed.email)) {
    return { error: "That email is already assigned to a staff account." };
  }

  try {
    await upsertStaffUserRecord({
      id: staffUserId(parsed.username),
      name: parsed.name,
      username: parsed.username,
      email: parsed.email,
      title: parsed.title,
      role: parsed.role,
      password: parsed.password ?? "",
      passwordChanged: false,
    });
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
}) {
  const session = await requireAdmin();
  const parsed = parseStaff({ ...input, requirePassword: false });
  if ("error" in parsed) return parsed;

  const store = await getFreshStore();
  const user = (store.users ?? []).find((entry) => entry.id === input.id);
  if (!user) {
    return { error: "Staff account not found." };
  }
  const taken = (store.users ?? []).some(
    (entry) => entry.id !== input.id && entry.username.trim().toLowerCase() === parsed.username.toLowerCase(),
  );
  if (taken) {
    return { error: "That username is already in use." };
  }
  if (parsed.email && (store.users ?? []).some((entry) => entry.id !== input.id && entry.email?.toLowerCase() === parsed.email)) {
    return { error: "That email is already assigned to a staff account." };
  }
  const admins = (store.users ?? []).filter((entry) => entry.role === "admin");
  if (
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

export async function updateOwnerPermissions(userId: string, permissions: StaffPermissions) {
  await requireAdmin();
  const store = await getFreshStore();
  const user = store.users.find((entry) => entry.id === userId);
  if (!user || user.role !== "cashier") return { error: "Owner account not found." };

  const normalized = Object.fromEntries(
    Object.keys(DEFAULT_STAFF_PERMISSIONS).map((key) => [
      key,
      permissions[key as keyof StaffPermissions] === true,
    ]),
  ) as StaffPermissions;

  try {
    await upsertStaffUserRecord({ ...user, permissions: normalized });
  } catch (error) {
    return { error: error instanceof Error ? error.message : "Could not save Owner permissions." };
  }
  refresh();
  return { ok: true };
}

export async function deleteStaffUser(id: string) {
  const session = await getSession();
  if (!session || (session.role !== "admin" && session.role !== "cashier")) {
    throw new Error("Only an Owner or admin can manage staff.");
  }
  if (session.userId === id) {
    return { error: "You cannot delete the account you are using." };
  }

  const store = await getStore();
  const user = store.users.find((entry) => entry.id === id);
  if (!user) {
    return { error: "Staff account not found." };
  }
  if (session.role === "cashier" && user.role !== "barista") {
    return { error: "Owners can only delete Barista accounts." };
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
    if (!user || user.role === "admin") {
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
        error = "Use a barista account to clock in here.";
        return;
      }
      if (openShifts.some((shift) => shift.userId === user.id)) {
        punched = { id: user.id, name: user.name, username: user.username };
        error = `${user.name} is already clocked in.`;
        return;
      }
      activity = appendPunch(store, user, "login", "barista");
      punched = { id: user.id, name: user.name, username: user.username };
      return;
    }

    const userId = String(input.userId ?? "").trim();
    const open = openShifts.find((shift) => shift.userId === userId) ?? (userId ? null : openShifts[0]);
    if (!open) {
      error = "That barista is not clocked in.";
      return;
    }
    const user = store.users.find((entry) => entry.id === open.userId);
    if (!user) {
      error = "Barista account not found.";
      return;
    }
    if (!hasBaristaCredentials(user, input.username ?? "", input.password ?? "")) {
      error = "Use the on-shift Barista's own username and password to clock out.";
      return;
    }
    activity = appendPunch(store, user, "logout", "barista");
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
  await requireAdmin();

  if (!input.loginId && !input.logoutId) {
    return { error: "No in / out record was selected." };
  }

  const ids = [input.loginId, input.logoutId].filter((id): id is string => Boolean(id));
  const store = await getStore();
  const existingIds = new Set(store.loginActivity.map((entry) => entry.id));
  const found = ids.some((id) => existingIds.has(id));
  if (!found) return { error: "In / out record not found." };

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
