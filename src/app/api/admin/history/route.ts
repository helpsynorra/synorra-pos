import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { parseDrinkStyle, parseStoredOrderAddons } from "@/lib/menu";
import { parsePayment } from "@/lib/payments";
import { supabaseAdmin } from "@/lib/store";
import { phDateRangeUtcBounds } from "@/lib/datetime";
import type { LoginActivity, Order, OrderItem, RestockRecord, UsageLog } from "@/lib/types";

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const PAGE_SIZE = 50;

function isValidDate(value: string) {
  if (!DATE_PATTERN.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

type HistoryOrderRow = {
  id: string;
  owner_id: string | null;
  created_at: string;
  barista_name: string;
  barista_user_id: string | null;
  subtotal: number | string | null;
  discount: number | string | null;
  promo_label: string | null;
  total: number | string;
  payment_method: string | null;
  ticket_no: string | null;
  paid: number | string | null;
  change: number | string | null;
  voided: boolean | null;
  voided_by: string | null;
  voided_by_name: string | null;
  void_reason: string | null;
  waste_reason: string | null;
  waste_baristas: unknown;
  record_type: string | null;
};

type HistoryItemRow = {
  order_id: string;
  product_id_snapshot: string;
  name_snapshot: string;
  category_snapshot: string | null;
  category_type_snapshot: string | null;
  qty: number | string;
  price_snapshot: number | string;
  style: unknown;
  addons: unknown;
  service_mode: string | null;
};

function mapOrders(rows: HistoryOrderRow[], itemRows: HistoryItemRow[]): Order[] {
  const itemsByOrder = new Map<string, OrderItem[]>();
  for (const row of itemRows) {
    const items = itemsByOrder.get(row.order_id) ?? [];
    items.push({
      productId: row.product_id_snapshot,
      name: row.name_snapshot,
      qty: Number(row.qty),
      price: Number(row.price_snapshot),
      category: row.category_snapshot ?? undefined,
      categoryType: row.category_type_snapshot ?? undefined,
      style: parseDrinkStyle(row.style),
      addons: parseStoredOrderAddons(row.addons),
      serviceMode:
        row.service_mode === "dine-in" || row.service_mode === "take-out"
          ? row.service_mode
          : undefined,
    });
    itemsByOrder.set(row.order_id, items);
  }

  return rows.map((row) => ({
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
    recordType:
      row.payment_method === "waste" || row.record_type === "Waste"
        ? "Waste"
        : row.record_type === "Purchase"
          ? "Purchase"
          : "Sale",
  }));
}

export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session || session.role !== "cashier") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const params = request.nextUrl.searchParams;
  const from = params.get("from") ?? "";
  const to = params.get("to") ?? "";
  const kind = params.get("kind") ?? "";
  const includeActivity = params.get("includeActivity") !== "false";
  const page = Number(params.get("page") ?? "1");
  if (
    !isValidDate(from) ||
    !isValidDate(to) ||
    from > to ||
    !["transactions", "restocks", "usage"].includes(kind) ||
    !Number.isSafeInteger(page) ||
    page < 1 ||
    (page - 1) * PAGE_SIZE > Number.MAX_SAFE_INTEGER
  ) {
    return NextResponse.json({ error: "Provide a valid history kind, date range, and page." }, { status: 400 });
  }

  const startRow = (page - 1) * PAGE_SIZE;
  const dateBounds = phDateRangeUtcBounds(from, to);
  if (!dateBounds) {
    return NextResponse.json({ error: "Provide a valid history kind, date range, and page." }, { status: 400 });
  }
  const { start: startDate, endExclusive: endDate } = dateBounds;

  try {
    const supabase = supabaseAdmin();
    if (kind === "restocks") {
      const { data, error, count } = await supabase
        .from("restocks")
        .select("id, owner_id, inventory_item_id, item_name_snapshot, quantity_added, purchase_qty, purchase_unit, unit_cost, created_at", { count: "exact" })
        .eq("owner_id", session.userId)
        .gte("created_at", startDate)
        .lt("created_at", endDate)
        .order("created_at", { ascending: true })
        .range(startRow, startRow + PAGE_SIZE - 1);
      if (error) throw new Error(`Unable to load restock history: ${error.message}`);
      const restocks: RestockRecord[] = (data ?? []).map((row) => ({
        id: row.id,
        ownerId: row.owner_id ?? undefined,
        inventoryItemId: row.inventory_item_id ?? undefined,
        itemName: row.item_name_snapshot,
        quantityAdded: Number(row.quantity_added),
        purchaseQty: row.purchase_qty == null ? undefined : Number(row.purchase_qty),
        purchaseUnit: row.purchase_unit ?? undefined,
        unitCost: row.unit_cost == null ? undefined : Number(row.unit_cost),
        date: row.created_at,
      }));
      const total = count ?? 0;
      return NextResponse.json({ restocks, page, pageSize: PAGE_SIZE, total, hasMore: startRow + restocks.length < total }, {
        headers: { "Cache-Control": "private, no-store" },
      });
    }

    if (kind === "usage") {
      const { data: orderRows, error: orderError, count } = await supabase
        .from("orders")
        .select("id, owner_id, created_at, barista_name, barista_user_id, subtotal, discount, promo_label, total, payment_method, ticket_no, paid, change, voided, voided_by, voided_by_name, void_reason, waste_reason, waste_baristas, deleted_at, record_type", { count: "exact" })
        .eq("owner_id", session.userId)
        .is("deleted_at", null)
        .gte("created_at", startDate)
        .lt("created_at", endDate)
        .order("created_at", { ascending: false })
        .range(startRow, startRow + PAGE_SIZE - 1);
      if (orderError) throw new Error(`Unable to load usage logbook orders: ${orderError.message}`);
      const orderIds = (orderRows ?? []).map((row) => row.id);
      const { data: logRows, error, count: logCount } = orderIds.length
        ? await supabase
            .from("usage_logs")
            .select("id, owner_id, order_id, order_item_id, inventory_item_id, item_name_snapshot, used_amount, unit, created_at", { count: "exact" })
            .eq("owner_id", session.userId)
            .in("order_id", orderIds)
            .order("created_at", { ascending: false })
            .range(0, PAGE_SIZE * 10 - 1)
        : { data: [], error: null, count: 0 };
      if (error) throw new Error(`Unable to load usage logbook: ${error.message}`);
      const usageLogs: UsageLog[] = (logRows ?? []).map((row) => ({
        id: row.id,
        ownerId: row.owner_id ?? undefined,
        orderId: row.order_id ?? "",
        orderItemId: row.order_item_id ?? "",
        inventoryItemId: row.inventory_item_id ?? undefined,
        itemName: row.item_name_snapshot,
        usedAmount: Number(row.used_amount),
        unit: row.unit,
        date: row.created_at,
      }));
      const { data: itemRows, error: itemError } = orderIds.length
        ? await supabase
            .from("order_items")
            .select("order_id, product_id_snapshot, name_snapshot, category_snapshot, category_type_snapshot, qty, price_snapshot, style, addons, service_mode")
            .eq("owner_id", session.userId)
            .in("order_id", orderIds)
        : { data: [], error: null };
      if (itemError) throw new Error(`Unable to load usage order items: ${itemError.message}`);
      const orders = mapOrders(orderRows ?? [], itemRows ?? []);
      const total = count ?? 0;
      return NextResponse.json({
        usageLogs,
        orders,
        page,
        pageSize: PAGE_SIZE,
        total,
        hasMore: startRow + orders.length < total,
        usageLogsTruncated: (logCount ?? 0) > usageLogs.length,
      }, {
        headers: { "Cache-Control": "private, no-store" },
      });
    }

    const { data: rows, error, count } = await supabase
      .from("orders")
      .select("id, owner_id, created_at, barista_name, barista_user_id, subtotal, discount, promo_label, total, payment_method, ticket_no, paid, change, voided, voided_by, voided_by_name, void_reason, waste_reason, waste_baristas, deleted_at, record_type", { count: "exact" })
      .eq("owner_id", session.userId)
      .is("deleted_at", null)
      .gte("created_at", startDate)
      .lt("created_at", endDate)
      .order("created_at", { ascending: false })
      .range(startRow, startRow + PAGE_SIZE - 1);
    if (error) throw new Error(`Unable to load transaction history: ${error.message}`);
    const orderIds = (rows ?? []).map((row) => row.id);
    const { data: itemRows, error: itemError } = orderIds.length
      ? await supabase
          .from("order_items")
          .select("order_id, product_id_snapshot, name_snapshot, category_snapshot, category_type_snapshot, qty, price_snapshot, style, addons, service_mode")
          .eq("owner_id", session.userId)
          .in("order_id", orderIds)
      : { data: [], error: null };
    if (itemError) throw new Error(`Unable to load transaction items: ${itemError.message}`);
    const orders = mapOrders(rows ?? [], itemRows ?? []);
    const { data: activityRows, error: activityError } = includeActivity
      ? await supabase
          .from("login_activity")
          .select("id, owner_id, user_id, username, name, role, type, at, photo_path")
          .eq("owner_id", session.userId)
          .gte("at", startDate)
          .lt("at", endDate)
          .order("at", { ascending: false })
          .range(0, PAGE_SIZE - 1)
      : { data: [], error: null };
    if (activityError) throw new Error(`Unable to load transaction staff activity: ${activityError.message}`);
    const loginActivity: LoginActivity[] = (activityRows ?? []).map((row) => ({
      id: row.id,
      ownerId: row.owner_id ?? undefined,
      userId: row.user_id ?? row.id,
      username: row.username,
      name: row.name,
      role: row.role,
      type: row.type,
      at: row.at,
      photoPath: row.photo_path ?? undefined,
    }));
    const total = count ?? 0;
    return NextResponse.json({
      orders,
      loginActivity,
      page,
      pageSize: PAGE_SIZE,
      total,
      hasMore: startRow + orders.length < total,
    }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Unable to load Admin history." },
      { status: 500, headers: { "Cache-Control": "private, no-store" } },
    );
  }
}
