import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { parseDrinkStyle, parseStoredOrderAddons } from "@/lib/menu";
import { parsePayment } from "@/lib/payments";
import { supabaseAdmin } from "@/lib/store";
import type { Order, OrderItem } from "@/lib/types";

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const PAGE_SIZE = 50;

function isValidDate(value: string) {
  if (!DATE_PATTERN.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session || session.role !== "cashier") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const from = request.nextUrl.searchParams.get("from") ?? "";
  const to = request.nextUrl.searchParams.get("to") ?? "";
  const page = Number(request.nextUrl.searchParams.get("page") ?? "1");
  if (
    !isValidDate(from) ||
    !isValidDate(to) ||
    from > to ||
    !Number.isSafeInteger(page) ||
    page < 1
  ) {
    return NextResponse.json(
      { error: "Provide valid dates and a positive page number." },
      { status: 400 },
    );
  }

  const endDay = new Date(`${to}T00:00:00.000Z`);
  endDay.setUTCDate(endDay.getUTCDate() + 1);
  const endDate = `${endDay.toISOString().slice(0, 10)}T00:00:00+08:00`;
  const startDate = `${from}T00:00:00+08:00`;
  const startRow = (page - 1) * PAGE_SIZE;

  try {
    const supabase = supabaseAdmin();
    const { data: rows, error, count } = await supabase
      .from("orders")
      .select(
        "id, owner_id, created_at, barista_name, barista_user_id, subtotal, discount, promo_label, total, payment_method, ticket_no, paid, change, voided, voided_by, voided_by_name, void_reason, waste_reason, waste_baristas, record_type",
        { count: "exact" },
      )
      .eq("owner_id", session.userId)
      .is("deleted_at", null)
      .gte("created_at", startDate)
      .lt("created_at", endDate)
      .or("payment_method.is.null,payment_method.neq.waste")
      .or("record_type.is.null,record_type.neq.Waste")
      .not("id", "ilike", "waste-%")
      .order("created_at", { ascending: false })
      .range(startRow, startRow + PAGE_SIZE - 1);
    if (error) throw new Error(`Unable to read recent orders: ${error.message}`);

    const orderIds = (rows ?? []).map((row) => row.id);
    const { data: itemRows, error: itemError } = orderIds.length
      ? await supabase
          .from("order_items")
          .select("order_id, product_id_snapshot, name_snapshot, category_snapshot, category_type_snapshot, qty, price_snapshot, style, addons, service_mode")
          .eq("owner_id", session.userId)
          .in("order_id", orderIds)
      : { data: [], error: null };
    if (itemError) throw new Error(`Unable to read recent order items: ${itemError.message}`);

    const itemsByOrder = new Map<string, OrderItem[]>();
    for (const item of itemRows ?? []) {
      const current = itemsByOrder.get(item.order_id) ?? [];
      current.push({
        productId: item.product_id_snapshot,
        name: item.name_snapshot,
        qty: Number(item.qty),
        price: Number(item.price_snapshot),
        category: item.category_snapshot ?? undefined,
        categoryType: item.category_type_snapshot ?? undefined,
        style: parseDrinkStyle(item.style),
        addons: parseStoredOrderAddons(item.addons),
        serviceMode:
          item.service_mode === "dine-in" || item.service_mode === "take-out"
            ? item.service_mode
            : undefined,
      });
      itemsByOrder.set(item.order_id, current);
    }

    const orders: Order[] = (rows ?? []).map((row) => ({
      id: row.id,
      ownerId: row.owner_id ?? undefined,
      createdAt: row.created_at,
      baristaName: row.barista_name,
      baristaUserId: row.barista_user_id ?? undefined,
      items: itemsByOrder.get(row.id) ?? [],
      subtotal: row.subtotal == null ? undefined : Number(row.subtotal),
      discount: row.discount == null ? undefined : Number(row.discount),
      promoLabel: row.promo_label ?? undefined,
      total: Number(row.total),
      paymentMethod: parsePayment(row.payment_method),
      serviceMode: itemsByOrder.get(row.id)?.find((item) => item.serviceMode)?.serviceMode,
      ticketNo: row.ticket_no ?? undefined,
      paid: row.paid == null ? undefined : Number(row.paid),
      change: row.change == null ? undefined : Number(row.change),
      voided: row.voided === true,
      voidedBy: row.voided_by ?? undefined,
      voidedByName: row.voided_by_name ?? undefined,
      voidReason: row.void_reason ?? undefined,
      wasteReason: row.waste_reason ?? undefined,
      wasteBaristas: Array.isArray(row.waste_baristas)
        ? row.waste_baristas.map(String).filter(Boolean)
        : undefined,
      recordType: row.record_type === "Purchase" ? "Purchase" : "Sale",
    }));

    return NextResponse.json(
      {
        orders,
        page,
        pageSize: PAGE_SIZE,
        total: count ?? 0,
        hasMore: startRow + orders.length < (count ?? 0),
      },
      { headers: { "Cache-Control": "private, no-store" } },
    );
  } catch (error) {
    return NextResponse.json(
      {
        error: error instanceof Error ? error.message : "Unable to load recent orders.",
      },
      { status: 500 },
    );
  }
}
