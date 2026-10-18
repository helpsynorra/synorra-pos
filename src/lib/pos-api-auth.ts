import { createHmac, timingSafeEqual } from "node:crypto";

export type PosApiClaims = {
  userId: string;
  username: string;
  name: string;
  role: "admin" | "cashier" | "barista";
  exp: number;
};

const TOKEN_LIFETIME_SECONDS = 60 * 60 * 12;

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
    throw new Error("A server-only signing key is required for the POS API.");
  }
  return key;
}

function signature(payload: string) {
  return createHmac("sha256", signingKey()).update(payload).digest("base64url");
}

export function createPosApiToken(
  claims: Omit<PosApiClaims, "exp">,
): string {
  const payload = Buffer.from(
    JSON.stringify({
      ...claims,
      exp: Math.floor(Date.now() / 1000) + TOKEN_LIFETIME_SECONDS,
    }),
  ).toString("base64url");
  return `${payload}.${signature(payload)}`;
}

export function readPosApiToken(authorization: string | null): PosApiClaims | null {
  if (!authorization?.startsWith("Bearer ")) return null;

  const token = authorization.slice(7).trim();
  const [payload, suppliedSignature, extra] = token.split(".");
  if (!payload || !suppliedSignature || extra) return null;

  try {
    const expected = Buffer.from(signature(payload), "base64url");
    const supplied = Buffer.from(suppliedSignature, "base64url");
    if (expected.length !== supplied.length || !timingSafeEqual(expected, supplied)) {
      return null;
    }

    const claims = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as PosApiClaims;
    const validRole = ["admin", "cashier", "barista"].includes(claims.role);
    if (
      !validRole ||
      typeof claims.userId !== "string" ||
      typeof claims.username !== "string" ||
      typeof claims.name !== "string" ||
      typeof claims.exp !== "number" ||
      claims.exp <= Math.floor(Date.now() / 1000)
    ) {
      return null;
    }
    return claims;
  } catch {
    return null;
  }
}
