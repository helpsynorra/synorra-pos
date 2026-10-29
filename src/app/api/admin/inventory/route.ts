import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/store";
import type { InventoryItem } from "@/lib/types";

const PAGE_SIZE = 50;

export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session || session.role !== "cashier") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const page = Number(request.nextUrl.searchParams.get("page") ?? "1");
  if (!Number.isSafeInteger(page) || page < 1 || (page - 1) * PAGE_SIZE > Number.MAX_SAFE_INTEGER) {
    return NextResponse.json({ error: "Provide a positive page number." }, { status: 400 });
  }

  try {
    const startRow = (page - 1) * PAGE_SIZE;
    const { data, error, count } = await supabaseAdmin()
      .from("inventory_items")
      .select("id, owner_id, name, unit, cost, stock, max_stock, reorder_threshold, opening_stock, purchase_unit_size, cup_usage_amount, cups_make, inventory_type, cup_size", { count: "exact" })
      .eq("owner_id", session.userId)
      .order("created_at", { ascending: true })
      .order("id", { ascending: true })
      .range(startRow, startRow + PAGE_SIZE - 1);
    if (error) throw new Error(`Unable to load inventory: ${error.message}`);

    const inventory: InventoryItem[] = (data ?? []).map((row) => ({
      id: row.id,
      ownerId: row.owner_id ?? undefined,
      name: row.name,
      unit: row.unit,
      cost: Number(row.cost),
      stock: Number(row.stock),
      maxStock: Number(row.max_stock),
      reorderThreshold: row.reorder_threshold == null ? undefined : Number(row.reorder_threshold),
      openingStock: row.opening_stock == null ? undefined : Number(row.opening_stock),
      purchaseUnitSize: row.purchase_unit_size == null ? undefined : Number(row.purchase_unit_size),
      cupUsageAmount: row.cup_usage_amount == null ? undefined : Number(row.cup_usage_amount),
      cupsMake: row.cups_make == null ? undefined : Number(row.cups_make),
      inventoryType: typeof row.inventory_type === "string" && row.inventory_type.trim() ? row.inventory_type.trim() : undefined,
      cupSize: typeof row.cup_size === "string" && row.cup_size.trim() ? row.cup_size.trim() : undefined,
    }));
    const total = count ?? 0;
    return NextResponse.json({
      inventory,
      page,
      pageSize: PAGE_SIZE,
      total,
      hasMore: startRow + inventory.length < total,
    }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Unable to load inventory." },
      { status: 500, headers: { "Cache-Control": "private, no-store" } },
    );
  }
}
