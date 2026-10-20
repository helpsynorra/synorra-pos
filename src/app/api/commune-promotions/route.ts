import { timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/store";

export const runtime = "nodejs";

function authorized(request: NextRequest): boolean {
  const configured = process.env.COMMUNE_PROMOTION_SHARED_SECRET?.trim();
  const supplied = request.headers.get("x-commune-promotion-secret") ?? "";
  if (!configured || configured.length < 32 || !supplied) return false;
  const expectedBytes = Buffer.from(configured);
  const suppliedBytes = Buffer.from(supplied);
  return expectedBytes.length === suppliedBytes.length &&
    timingSafeEqual(expectedBytes, suppliedBytes);
}

function responseError(error: string, status: number) {
  return NextResponse.json({ ok: false, error }, { status, headers: { "Cache-Control": "no-store" } });
}

export async function POST(request: NextRequest) {
  if (!process.env.COMMUNE_PROMOTION_SHARED_SECRET?.trim()) {
    return responseError("Commune promotion integration is not configured.", 503);
  }
  if (!authorized(request)) return responseError("Unauthorized promotion integration request.", 401);

  try {
    const body = await request.json() as Record<string, unknown>;
    const action = String(body.action ?? "");
    const code = String(body.code ?? "").replace(/\s+/g, "").toUpperCase();
    if (!/^(?:[A-Z0-9]{6}|[A-Z0-9]{1,16}-[A-Z0-9]{6})$/.test(code)) {
      return responseError("Enter a valid promotion voucher.", 400);
    }

    const { data: row, error: readError } = await supabaseAdmin()
      .from("commune_promotions")
      .select("code,discount_type,discount_value,expires_at,redeemed_at")
      .eq("code", code)
      .maybeSingle();
    if (readError) throw readError;
    if (!row) return responseError("Invalid Commune promotion voucher.", 404);
    const promotion = {
      code: String(row.code),
      discountType: String(row.discount_type),
      discountValue: Number(row.discount_value),
      expiresAt: String(row.expires_at),
      redeemedAt: row.redeemed_at ? String(row.redeemed_at) : null,
    };
    if (promotion.redeemedAt) return responseError("Commune promotion voucher already used.", 409);
    if (Date.parse(promotion.expiresAt) <= Date.now()) {
      return responseError("Promotion voucher has expired.", 409);
    }

    if (action === "validate") {
      return NextResponse.json({
        ok: true,
        promotion: {
          code: promotion.code,
          discountType: promotion.discountType,
          discountValue: promotion.discountValue,
          expiresAt: promotion.expiresAt,
        },
      }, { headers: { "Cache-Control": "no-store" } });
    }

    if (action !== "redeem") return responseError("Unsupported promotion action.", 400);
    const orderId = typeof body.orderId === "string" ? body.orderId.trim() : "";
    const order = body.order && typeof body.order === "object"
      ? body.order as Record<string, unknown>
      : null;
    const items = Array.isArray(order?.items) ? order.items as Record<string, unknown>[] : [];
    const subtotal = Math.max(0, Math.round(Number(order?.subtotal) || 0));
    const discount = Math.max(0, Math.round(Number(order?.discount) || 0));
    if (!orderId || !order) return responseError("Order details are required to redeem this voucher.", 400);

    let expectedDiscount: number;
    if (promotion.discountType === "item") {
      const index = Number.isInteger(order.promoItemIndex) ? Number(order.promoItemIndex) : -1;
      const quantity = Number.isInteger(order.promoItemQty) ? Number(order.promoItemQty) : 0;
      const freeQuantity = Math.max(1, Math.floor(promotion.discountValue));
      const selected = items[index];
      if (!selected || quantity !== freeQuantity || Number(selected.qty) < freeQuantity) {
        return responseError("Select a valid quantity for the free item promotion.", 400);
      }
      const addons = Array.isArray(selected.addons) ? selected.addons as Record<string, unknown>[] : [];
      const unitPrice = Number(selected.price) + addons.reduce((sum, addon) =>
        sum + (Number(addon.price) || 0) * Math.max(1, Number(addon.qty) || 1), 0);
      expectedDiscount = Math.round(unitPrice * freeQuantity);
    } else {
      expectedDiscount = Math.min(subtotal, Math.round(
        promotion.discountType === "amount"
          ? promotion.discountValue
          : subtotal * promotion.discountValue / 100,
      ));
    }
    if (discount !== expectedDiscount) {
      return responseError("Promotion discount does not match this voucher.", 400);
    }

    const redeemedAt = new Date().toISOString();
    const { data, error } = await supabaseAdmin()
      .from("commune_promotions")
      .update({ redeemed_at: redeemedAt, redeemed_order_id: orderId })
      .eq("code", promotion.code)
      .is("redeemed_at", null)
      .gt("expires_at", redeemedAt)
      .select("code")
      .maybeSingle();
    if (error) throw error;
    if (!data) return responseError("Promotion voucher is no longer available.", 409);

    return NextResponse.json({ ok: true }, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    console.error("Commune promotion integration failed:", error);
    return responseError("Unable to process this promotion voucher.", 500);
  }
}
