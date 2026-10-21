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
    if (action === "admin_summary") {
      const db = supabaseAdmin();
      const now = new Date().toISOString();
      const [available, hostRows, redeemed] = await Promise.all([
        db.from("commune_promotions")
          .select("code", { count: "exact", head: true })
          .eq("approval_status", "approved")
          .is("redeemed_at", null)
          .gt("expires_at", now),
        db.from("commune_promotions")
          .select("event_host,expires_at,redeemed_at")
          .eq("approval_status", "approved"),
        db.from("commune_promotions")
          .select("code,event_host,expires_at,redeemed_at,redeemed_order_id")
          .eq("approval_status", "approved")
          .not("redeemed_at", "is", null)
          .gt("expires_at", now)
          .order("redeemed_at", { ascending: false }),
      ]);
      if (available.error) throw available.error;
      if (hostRows.error) throw hostRows.error;
      if (redeemed.error) throw redeemed.error;
      const { data: pendingRows, error: pendingError } = await db.from("commune_promotions")
        .select("batch_id,code,event_host,created_at,expires_at,discount_type,discount_value")
        .eq("approval_status", "pending")
        .eq("batch_ready", true)
        .not("batch_id", "is", null)
        .order("created_at", { ascending: true });
      if (pendingError) throw pendingError;
      const pendingBatches = new Map<string, {
        batchId: string;
        voucherCount: number;
        eventHost: string;
        createdAt: string;
        expiresAt: string;
        discountType: string;
        discountValue: number;
      }>();
      for (const row of pendingRows ?? []) {
        const batchId = String(row.batch_id);
        const batch = pendingBatches.get(batchId) ?? {
          batchId,
          voucherCount: 0,
          eventHost: String(row.event_host ?? "").trim() || "No host assigned",
          createdAt: String(row.created_at),
          expiresAt: String(row.expires_at),
          discountType: String(row.discount_type),
          discountValue: Number(row.discount_value),
        };
        batch.voucherCount += 1;
        pendingBatches.set(batchId, batch);
      }
      const manilaDateOnly = (value: string) => {
        const date = new Date(value);
        if (!Number.isFinite(date.getTime())) return "";
        const parts = new Intl.DateTimeFormat("en-US", {
          timeZone: "Asia/Manila",
          year: "numeric",
          month: "2-digit",
          day: "2-digit",
        }).formatToParts(date);
        const part = (type: string) => parts.find((entry) => entry.type === type)?.value ?? "";
        return `${part("year")}-${part("month")}-${part("day")}`;
      };
      const hostCounts = new Map<string, { availableCount: number; redeemedCount: number }>();
      const expirationGroups = new Map<string, Map<string, { availableCount: number; redeemedCount: number }>>();
      for (const row of hostRows.data ?? []) {
        if (Date.parse(String(row.expires_at)) <= Date.now()) continue;
        const expiresOn = manilaDateOnly(String(row.expires_at));
        if (!expiresOn) continue;
        const name = String(row.event_host ?? "").trim() || "No host assigned";
        const updateCounts = (counts: { availableCount: number; redeemedCount: number }) => {
          if (row.redeemed_at) {
            counts.redeemedCount += 1;
          } else {
            counts.availableCount += 1;
          }
        };
        const totalHostCounts = hostCounts.get(name) ?? { availableCount: 0, redeemedCount: 0 };
        updateCounts(totalHostCounts);
        hostCounts.set(name, totalHostCounts);
        const hostsForDate = expirationGroups.get(expiresOn) ?? new Map<string, { availableCount: number; redeemedCount: number }>();
        const dateHostCounts = hostsForDate.get(name) ?? { availableCount: 0, redeemedCount: 0 };
        updateCounts(dateHostCounts);
        hostsForDate.set(name, dateHostCounts);
        expirationGroups.set(expiresOn, hostsForDate);
      }
      const expirationSummaries = [...expirationGroups]
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([expiresOn, hostMap]) => {
          const eventHosts = [...hostMap].map(([name, counts]) => ({ name, ...counts }));
          return {
            expiresOn,
            availableCount: eventHosts.reduce((sum, host) => sum + host.availableCount, 0),
            redeemedCount: eventHosts.reduce((sum, host) => sum + host.redeemedCount, 0),
            eventHosts,
          };
        });
      return NextResponse.json({
        ok: true,
        availableCount: available.count ?? 0,
        eventHosts: [...hostCounts].map(([name, counts]) => ({ name, ...counts })),
        expirationSummaries,
        pendingBatches: [...pendingBatches.values()],
        redeemed: (redeemed.data ?? []).map((row) => ({
          code: String(row.code),
          eventHost: String(row.event_host ?? ""),
          expiresOn: manilaDateOnly(String(row.expires_at)),
          redeemedAt: String(row.redeemed_at),
          orderId: String(row.redeemed_order_id ?? ""),
        })),
      }, { headers: { "Cache-Control": "no-store" } });
    }
    if (action === "approve_batch" || action === "decline_batch") {
      const batchId = typeof body.batchId === "string" ? body.batchId.trim() : "";
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(batchId)) {
        return responseError("Enter a valid promotion batch ID.", 400);
      }
      const status = action === "approve_batch" ? "approved" : "declined";
      const { data, error } = await supabaseAdmin().rpc("review_commune_promotion_batch", {
        p_batch_id: batchId,
        p_status: status,
      });
      if (error) throw error;
      if (!Number(data)) return responseError("This batch was already reviewed or no longer exists.", 409);
      return NextResponse.json({ ok: true, batchId, status, voucherCount: Number(data) }, {
        headers: { "Cache-Control": "no-store" },
      });
    }
    const code = String(body.code ?? "").replace(/\s+/g, "").toUpperCase();
    if (!/^(?:[A-Z0-9]{6}|[A-Z0-9]{1,16}-[A-Z0-9]{6})$/.test(code)) {
      return responseError("Enter a valid promotion voucher.", 400);
    }

    const { data: row, error: readError } = await supabaseAdmin()
      .from("commune_promotions")
      .select("code,discount_type,discount_value,event_host,expires_at,redeemed_at,approval_status")
      .eq("code", code)
      .maybeSingle();
    if (readError) throw readError;
    if (!row) return responseError("Invalid Commune promotion voucher.", 404);
    if (row.approval_status !== "approved") return responseError("This Commune promotion voucher is not available.", 404);
    const promotion = {
      code: String(row.code),
      discountType: String(row.discount_type),
      discountValue: Number(row.discount_value),
      eventHost: String(row.event_host ?? ""),
      expiresAt: String(row.expires_at),
      redeemedAt: row.redeemed_at ? String(row.redeemed_at) : null,
    };
    if (promotion.redeemedAt) return responseError("Commune promotion voucher already used.", 409);
    const expiryTime = Date.parse(promotion.expiresAt);
    if (!Number.isFinite(expiryTime) || expiryTime <= Date.now()) {
      return responseError("Promotion voucher has expired.", 409);
    }

    if (action === "validate") {
      return NextResponse.json({
        ok: true,
        promotion: {
          code: promotion.code,
          discountType: promotion.discountType,
          discountValue: promotion.discountValue,
          eventHost: promotion.eventHost,
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
      const freeQuantity = Math.max(1, Math.floor(promotion.discountValue));
      const rawSelections = Array.isArray(order.promoItemSelections)
        ? order.promoItemSelections
        : [{ index: order.promoItemIndex, qty: order.promoItemQty }];
      const selections = rawSelections.map((selection) => {
        if (!selection || typeof selection !== "object") return null;
        const value = selection as Record<string, unknown>;
        return {
          index: value.index,
          qty: value.qty,
        };
      });
      const validSelections = selections.every((selection) =>
        selection !== null &&
        Number.isInteger(selection.index) &&
        Number.isInteger(selection.qty) &&
        Number(selection.index) >= 0 &&
        Number(selection.index) < items.length &&
        Number(selection.qty) > 0,
      );
      const selectedQuantity = selections.reduce((sum, selection) =>
        sum + (selection ? Number(selection.qty) : 0), 0);
      const indices = selections.map((selection) => selection?.index);
      const uniqueIndices = new Set(indices).size === indices.length;
      if (!validSelections || !uniqueIndices || selectedQuantity !== freeQuantity || selectedQuantity > 3 || selectedQuantity < 1) {
        return responseError("Select a valid quantity for the free item promotion.", 400);
      }
      expectedDiscount = selections.reduce((discountTotal, selection) => {
        if (!selection) return discountTotal;
        const selected = items[Number(selection.index)];
        const lineQuantity = Number(selected.qty);
        if (!Number.isInteger(lineQuantity) || lineQuantity < Number(selection.qty)) return Number.NaN;
        const addons = Array.isArray(selected.addons) ? selected.addons as Record<string, unknown>[] : [];
        const unitPrice = Number(selected.price) + addons.reduce((sum, addon) =>
          sum + (Number(addon.price) || 0) * Math.max(1, Number(addon.qty) || 1), 0);
        return discountTotal + Math.round(unitPrice * Number(selection.qty));
      }, 0);
      if (!Number.isFinite(expectedDiscount)) {
        return responseError("Select a valid quantity for the free item promotion.", 400);
      }
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
    if (error) {
      if (error.message.includes("PROMO_EXPIRED")) {
        return responseError("Promotion voucher has expired.", 409);
      }
      throw error;
    }
    if (!data) {
      if (Date.parse(promotion.expiresAt) <= Date.now()) {
        return responseError("Promotion voucher has expired.", 409);
      }
      return responseError("Promotion voucher is no longer available.", 409);
    }

    return NextResponse.json({ ok: true }, { headers: { "Cache-Control": "no-store" } });
  } catch (error) {
    console.error("Commune promotion integration failed:", error);
    return responseError("Unable to process this promotion voucher.", 500);
  }
}
