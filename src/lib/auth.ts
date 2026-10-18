import { cookies } from "next/headers";
import { createHmac, timingSafeEqual } from "node:crypto";
import type { Session } from "@/lib/types";

export const SESSION_COOKIE = "commune_session";
const SESSION_LIFETIME_SECONDS = 60 * 60 * 12;

function signingKey() {
  const configured = process.env.POS_SESSION_SECRET?.trim();
  const key = configured && configured.length >= 32
    ? configured
    : process.env.SUPABASE_SECRET_KEY?.trim() ||
      process.env.commume_coffee_SUPABASE_SECRET_KEY?.trim() ||
      process.env.SUPABASE_SERVICE_ROLE_KEY?.trim() ||
      process.env.commume_coffee_SUPABASE_SERVICE_ROLE_KEY?.trim() ||
      process.env.SUPABASE_SERVICE_ROLE_KEY_2?.trim();
  if (!key || key.length < 32) {
    throw new Error("A server-only signing key is required for web sessions.");
  }
  return key;
}

function sessionSignature(payload: string) {
  return createHmac("sha256", signingKey()).update(payload).digest("base64url");
}

export function encodeSession(session: Session): string {
  const payload = Buffer.from(
    JSON.stringify({
      ...session,
      exp: Math.floor(Date.now() / 1000) + SESSION_LIFETIME_SECONDS,
    }),
  ).toString("base64url");
  return `${payload}.${sessionSignature(payload)}`;
}

export function decodeSession(value: string | undefined): Session | null {
  if (!value) return null;

  try {
    const [payload, suppliedSignature, extra] = value.split(".");
    if (!payload || !suppliedSignature || extra) return null;
    const expected = Buffer.from(sessionSignature(payload), "base64url");
    const supplied = Buffer.from(suppliedSignature, "base64url");
    if (
      expected.length !== supplied.length ||
      !timingSafeEqual(expected, supplied)
    ) {
      return null;
    }

    const parsed = JSON.parse(
      Buffer.from(payload, "base64url").toString("utf8"),
    ) as Session & { exp?: number };
    if (
      typeof parsed.userId !== "string" ||
      typeof parsed.username !== "string" ||
      typeof parsed.name !== "string" ||
      (parsed.role !== "admin" &&
        parsed.role !== "cashier" &&
        parsed.role !== "barista") ||
      typeof parsed.exp !== "number" ||
      parsed.exp <= Math.floor(Date.now() / 1000)
    ) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

export async function getSession(): Promise<Session | null> {
  const jar = await cookies();
  return decodeSession(jar.get(SESSION_COOKIE)?.value);
}

export function homeForRole(role: Session["role"]): string {
  if (role === "admin") return "/synorra-host";
  if (role === "cashier") return "/owner";
  return "/";
}

export function sessionCookieOptions() {
  const isSecureEnv =
    process.env.VERCEL === "1" ||
    Boolean(process.env.K_SERVICE) ||
    process.env.NODE_ENV === "production" ||
    Boolean(process.env.APP_URL?.startsWith("https://"));
  return {
    httpOnly: true,
    sameSite: (isSecureEnv ? "none" : "lax") as "none" | "lax",
    path: "/",
    maxAge: 60 * 60 * 12,
    secure: isSecureEnv,
  };
}
