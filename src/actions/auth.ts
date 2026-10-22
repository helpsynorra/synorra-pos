"use server";

import bcrypt from "bcryptjs";
import { createHash, randomBytes } from "node:crypto";
import nodemailer from "nodemailer";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import {
  SESSION_COOKIE,
  encodeSession,
  getSession,
  homeForRole,
  sessionCookieOptions,
} from "@/lib/auth";
import { getFreshStore, getStore, isRealSupabaseConfigured, recordAuthActivity, supabaseAdmin, upsertStaffUserRecord } from "@/lib/store";
import { loginPathForRole, normalizeLoginGates } from "@/lib/staff-gates";
import { parseLoginRole, parseRole, toSession } from "@/lib/users";

export type LoginState = {
  error?: string;
};

export type PasswordChangeState = { error?: string };
export type PasswordResetRequestState = { sent?: boolean; error?: string };
export type PasswordResetState = { reset?: boolean; error?: string };

function passwordResetTokenHash(token: string) {
  return createHash("sha256").update(token).digest("hex");
}

export async function requestOwnerPasswordReset(
  _prev: PasswordResetRequestState,
  formData: FormData,
): Promise<PasswordResetRequestState> {
  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return { error: "Enter a valid email address." };
  }

  const gmailAppPassword = process.env.GMAIL_APP_PASSWORD?.replace(/\s/g, "");
  const sender = "help.synorra@gmail.com";
  if (!gmailAppPassword || !isRealSupabaseConfigured()) {
    console.error("Owner password recovery is missing Gmail SMTP or Supabase server configuration.");
    return { error: "Password recovery is not available right now. Please try again later." };
  }

  try {
    const store = await getFreshStore();
    const owner = store.users.find(
      (user) =>
        user.role === "cashier" &&
        user.email?.trim().toLowerCase() === email &&
        user.password,
    );

    if (owner) {
      const supabase = supabaseAdmin();
      const token = randomBytes(32).toString("hex");
      const tokenHash = passwordResetTokenHash(token);
      const expiresAt = new Date(Date.now() + 60 * 60 * 1000).toISOString();

      const { error: clearError } = await supabase
        .from("staff_password_resets")
        .delete()
        .eq("staff_user_id", owner.id);
      if (clearError) throw clearError;

      const { error: insertError } = await supabase
        .from("staff_password_resets")
        .insert({ staff_user_id: owner.id, token_hash: tokenHash, expires_at: expiresAt });
      if (insertError) throw insertError;

      const appUrl = (process.env.APP_URL || "https://synorra-pos.click").replace(/\/+$/, "");
      const resetUrl = `${appUrl}/back-office/reset-password?token=${token}`;
      const mailer = nodemailer.createTransport({
        service: "gmail",
        auth: { user: sender, pass: gmailAppPassword },
      });
      try {
        await mailer.sendMail({
          from: { name: "Synorra", address: sender },
          to: email,
          subject: "Synorra: password recovery",
          text: `To create a new password, open this link: ${resetUrl}\n\nThis link expires in 1 hour. If you did not request this, ignore this email.`,
          html: `<!doctype html>
<html><body style="margin:0;background:#e7e7e7;font-family:Arial,Helvetica,sans-serif;color:#111;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#e7e7e7;padding:48px 16px;">
    <tr><td align="center">
      <table role="presentation" width="570" cellspacing="0" cellpadding="0" style="max-width:570px;width:100%;background:#fff;border-radius:3px;text-align:center;">
        <tr><td style="padding:28px 24px 0;color:#171717;font-size:26px;font-weight:700;letter-spacing:3px;">SYNORRA</td></tr>
        <tr><td style="padding:42px 24px 0;font-size:20px;">Password recovery</td></tr>
        <tr><td style="padding:24px 24px 0;font-size:14px;line-height:1.6;">To create a new password click on the button below</td></tr>
        <tr><td style="padding:38px 24px 0;"><a href="${resetUrl}" style="display:inline-block;background:#77b33d;color:#fff;text-decoration:none;font-size:13px;font-weight:700;padding:18px 24px;border-radius:3px;">CREATE A NEW PASSWORD</a></td></tr>
        <tr><td style="padding:42px 28px 0;font-size:12px;line-height:1.7;">If you have questions, contact <a href="mailto:${sender}" style="color:#1687c9;text-decoration:none;">Synorra Support</a>.<br/>We are happy to assist.</td></tr>
        <tr><td style="padding:28px 24px 24px;font-size:12px;">Sincerely, The Synorra team</td></tr>
      </table>
      <p style="padding-top:8px;color:#1687c9;font-size:12px;">© 2026 Synorra</p>
      <p style="color:#666;font-size:11px;">This link expires in 1 hour. If you did not request this, you can ignore this email.</p>
    </td></tr>
  </table>
</body></html>`,
        });
        console.info("Owner password recovery email accepted by Gmail SMTP.");
      } catch (sendError) {
        await supabase.from("staff_password_resets").delete().eq("token_hash", tokenHash);
        console.error("Gmail could not send the Owner password recovery email.", sendError);
        return { error: "We couldn't send the reset instructions right now. Please try again later." };
      }
    } else {
      console.info("Owner password recovery request did not match an eligible Owner account.");
    }

    // Keep the response identical for an unknown email and a known Owner email.
    return { sent: true };
  } catch (error) {
    console.error("Owner password recovery request failed.", error);
    return { error: "We couldn't send the reset instructions right now. Please try again later." };
  }
}

export async function resetOwnerPassword(
  _prev: PasswordResetState,
  formData: FormData,
): Promise<PasswordResetState> {
  const token = String(formData.get("token") ?? "").trim().toLowerCase();
  const password = String(formData.get("password") ?? "");
  const confirmation = String(formData.get("confirmPassword") ?? "");
  if (!/^[a-f0-9]{64}$/.test(token)) {
    return { error: "This reset link is invalid or expired. Request another reset." };
  }
  if (password.length < 8 || password.length > 128) {
    return { error: "Choose a password between 8 and 128 characters." };
  }
  if (password !== confirmation) {
    return { error: "The passwords do not match." };
  }
  if (!isRealSupabaseConfigured()) {
    return { error: "Password recovery is not available right now. Please try again later." };
  }

  try {
    const supabase = supabaseAdmin();
    const now = new Date().toISOString();
    const { data: reset, error: findError } = await supabase
      .from("staff_password_resets")
      .select("id, staff_user_id")
      .eq("token_hash", passwordResetTokenHash(token))
      .is("used_at", null)
      .gt("expires_at", now)
      .maybeSingle();
    if (findError) throw findError;
    if (!reset) {
      return { error: "This reset link is invalid or expired. Request another reset." };
    }

    // Claim the token before changing the password so it cannot be used twice.
    const { data: claimed, error: claimError } = await supabase
      .from("staff_password_resets")
      .update({ used_at: now })
      .eq("id", reset.id)
      .is("used_at", null)
      .gt("expires_at", now)
      .select("id")
      .maybeSingle();
    if (claimError) throw claimError;
    if (!claimed) {
      return { error: "This reset link is invalid or expired. Request another reset." };
    }

    const store = await getFreshStore();
    const owner = store.users.find(
      (user) => user.id === reset.staff_user_id && user.role === "cashier",
    );
    if (!owner) {
      return { error: "This reset link is invalid or expired. Request another reset." };
    }

    await upsertStaffUserRecord({
      ...owner,
      password: await bcrypt.hash(password, 12),
      passwordChanged: true,
    });
    return { reset: true };
  } catch (error) {
    console.error("Owner password reset failed.", error);
    return { error: "We couldn't reset your password right now. Please request a new link." };
  }
}

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

  // Login must search the global staff list. A stale Owner/Admin session can
  // otherwise scope getFreshStore() to one tenant and hide the Admin account.
  const store = await getFreshStore({ ownerId: null });
  const lowerUsername = username.toLowerCase();
  const user =
    selectedRole === "cashier"
      ? store.users.find(
          (entry) =>
            entry.role === "cashier" &&
            entry.email?.trim().toLowerCase() === email,
        )
      : store.users.find(
          (entry) =>
            entry.role === "admin" &&
            entry.username.trim().toLowerCase() === lowerUsername,
        ) ??
        store.users.find(
          (entry) =>
            entry.role === "admin" &&
            entry.name.trim().toLowerCase() === lowerUsername,
        );

  if (!user || !user.password) {
    return { error: "Invalid username or password." };
  }
  if (selectedRole === "cashier" && user.email?.trim().toLowerCase() !== email) {
    return { error: "Those credentials do not match a Synorra Owner account." };
  }

  const passwordMatches = user.password.startsWith("$2")
    ? await bcrypt.compare(password, user.password)
    : user.password === password || user.password.trim() === password.trim();
  if (!passwordMatches) {
    return { error: "Invalid username or password." };
  }

  const effectiveRole = parseRole(String(user.title ?? ""), user.role);
  if (selectedRole === "admin" && effectiveRole !== "admin") {
    return { error: "Those credentials are not for the Admin role." };
  }
  if (selectedRole === "cashier" && effectiveRole !== "cashier") {
    return { error: "Only Owner accounts can log in to the back-office." };
  }
  if (selectedRole === "cashier" && !user.passwordChanged) {
    return { error: "First log in to the POS with your email and temporary password to set your new password." };
  }

  if (!user.password.startsWith("$2")) {
    await upsertStaffUserRecord({
      ...user,
      password: await bcrypt.hash(user.password, 12),
    });
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

  const email = String(formData.get("email") ?? "").trim().toLowerCase();
  const password = String(formData.get("password") ?? "");
  const newPassword = String(formData.get("newPassword") ?? "");
  if (!email || !password || newPassword.length < 8) {
    return { error: "Enter your email, current password, and a new password with at least 8 characters." };
  }

  const store = await getFreshStore();
  const user = store.users.find((entry) => entry.id === session.userId && entry.role === "cashier");
  if (!user || user.email?.trim().toLowerCase() !== email || !user.password) {
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

