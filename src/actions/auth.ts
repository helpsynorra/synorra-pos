"use server";

import bcrypt from "bcryptjs";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import {
  SESSION_COOKIE,
  encodeSession,
  getSession,
  homeForRole,
  sessionCookieOptions,
} from "@/lib/auth";
import { getFreshStore, getStore, recordAuthActivity, upsertStaffUserRecord } from "@/lib/store";
import { loginPathForRole, normalizeLoginGates } from "@/lib/staff-gates";
import { parseLoginRole, parseRole, toSession } from "@/lib/users";

export type LoginState = {
  error?: string;
};

export type PasswordChangeState = { error?: string };

export async function login(
  _prev: LoginState,
  formData: FormData,
): Promise<LoginState> {
  const username = String(formData.get("username") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const password = String(formData.get("password") ?? "");
  const selectedRole = parseLoginRole(String(formData.get("role") ?? ""));

  if (!selectedRole) {
    return { error: "Select Admin or Owner." };
  }
  if (selectedRole === "admin" && (!username || !password)) {
    return { error: "Enter a username and password." };
  }
  if (selectedRole === "cashier" && !password) {
    return { error: "Enter your email and password." };
  }
  if (selectedRole === "cashier" && !email) {
    return { error: "Enter your Owner account email." };
  }

  const store = await getFreshStore();
  const lowerUsername = username.toLowerCase();
  const user = store.users.find(
    (entry) =>
      selectedRole === "cashier"
        ? entry.email?.trim().toLowerCase() === email
        : entry.username.trim().toLowerCase() === lowerUsername ||
          entry.name.trim().toLowerCase() === lowerUsername,
  );

  if (!user || !user.password) {
    return { error: "Those credentials do not match a Synorra staff account." };
  }
  if (selectedRole === "cashier" && user.email?.trim().toLowerCase() !== email) {
    return { error: "Those credentials do not match a Synorra Owner account." };
  }

  const passwordMatches = user.password.startsWith("$2")
    ? await bcrypt.compare(password, user.password)
    : user.password === password || user.password.trim() === password.trim();
  if (!passwordMatches) {
    return { error: "Those credentials do not match a Synorra staff account." };
  }

  const effectiveRole = parseRole(String(user.title ?? ""), user.role);
  if (selectedRole === "admin" && effectiveRole !== "admin") {
    return { error: "Those credentials are not for the Admin role." };
  }
  if (selectedRole === "cashier" && effectiveRole !== "cashier") {
    return { error: "Only Owner accounts can log in to the back-office." };
  }
  if (selectedRole === "cashier" && !user.passwordChanged) {
    return { error: "First log in to the POS with your email, username, and temporary password to set your new password." };
  }

  const session = toSession({ ...user, role: effectiveRole });
  await recordAuthActivity({
    userId: user.id,
    username: user.username,
    name: user.name,
    role: effectiveRole,
    type: "login",
  });
  const jar = await cookies();
  jar.set(SESSION_COOKIE, encodeSession(session), sessionCookieOptions());

  if (session.mustChangePassword) {
    redirect("/cashier/change-password");
  }

  redirect(homeForRole(session.role));
}

export async function changeCashierPassword(
  _prev: PasswordChangeState,
  formData: FormData,
): Promise<PasswordChangeState> {
  const session = await getSession();
  if (!session || session.role !== "cashier" || !session.mustChangePassword) {
    return { error: "This password change request is no longer valid. Sign in again." };
  }

  const username = String(formData.get("username") ?? "").trim().toLowerCase();
  const password = String(formData.get("password") ?? "");
  const newPassword = String(formData.get("newPassword") ?? "");
  if (username !== session.username.toLowerCase() || !password || newPassword.length < 8) {
    return { error: "Enter your username, current password, and a new password with at least 8 characters." };
  }

  const store = await getFreshStore();
  const user = store.users.find((entry) => entry.id === session.userId && entry.role === "cashier");
  if (!user || user.username.toLowerCase() !== username || !user.password) {
    return { error: "Those credentials do not match this Owner account." };
  }
  const passwordMatches = user.password.startsWith("$2")
    ? await bcrypt.compare(password, user.password)
    : user.password === password || user.password.trim() === password.trim();
  if (!passwordMatches) {
    return { error: "Those credentials do not match this Owner account." };
  }

  const updatedUser = {
    ...user,
    password: await bcrypt.hash(newPassword, 12),
    passwordChanged: true,
  };
  await upsertStaffUserRecord(updatedUser);
  const jar = await cookies();
  jar.set(SESSION_COOKIE, encodeSession({ ...toSession(updatedUser), mustChangePassword: false }), sessionCookieOptions());
  redirect(homeForRole("cashier"));
}

export async function logout() {
  const session = await getSession();
  if (session) {
    await recordAuthActivity({
      userId: session.userId,
      username: session.username,
      name: session.name,
      role: session.role,
      type: "logout",
    });
  }
  const jar = await cookies();
  jar.delete(SESSION_COOKIE);

  const gateRole =
    session?.role === "admin"
      ? "admin"
      : session?.role === "cashier"
        ? "cashier"
        : null;

  if (gateRole) {
    let loginPath = "/";
    try {
      const store = await getStore();
      const gates = normalizeLoginGates(store.loginGates);
      loginPath = loginPathForRole(gateRole, gates);
    } catch {
      // gate resolution failed — fall back to landing page
    }
    redirect(loginPath);
  }

  redirect("/");
}

