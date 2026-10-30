import bcrypt from "bcryptjs";
import { NextRequest, NextResponse } from "next/server";
import { phIsoTimestamp } from "@/lib/datetime";
import { ingredientsForOrderLine, roundQty } from "@/lib/inventory";
import {
  hydrateOrderLine,
  inferMenuCategoryType,
  normalizeMenuAddons,
  normalizeMenuCategoryType,
  normalizeMenuStyles,
  normalizeMenuTypeOptions,
  parseDrinkStyle,
  parseMenuImageOptions,
  parseStoredOrderAddons,
  stripMenuImage,
} from "@/lib/menu";
import { parsePayment } from "@/lib/payments";
import { createPosApiToken, readPosApiToken } from "@/lib/pos-api-auth";
import { pairLoginSessions } from "@/lib/staff-sessions";
import type { LoginActivity } from "@/lib/types";
import {
  createOrderAtomic,
  createRestockAtomic,
  deleteOwnerAccountAndData,
  deleteInventoryItemRecord,
  deleteRestockAtomic,
  editRestockAtomic,
  getFreshStore,
  getOwnerAccounts,
  insertLoginActivityRecord,
  insertVoidRequestRecord,
  legacyOwnerId,
  ownerIdForStaff,
  supabaseAdmin,
  upsertStaffUserRecord,
  updateStore,
  voidOrderAtomic,
  withStoreTenant,
} from "@/lib/store";
import type { InventoryItem, Order, OrderItem, VoidRequest } from "@/lib/types";
import { parseRole } from "@/lib/users";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Requested-With",
  "Cache-Control": "no-store, no-cache, must-revalidate",
};

function orderItemsFromApi(value: unknown): OrderItem[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((rawItem) => {
    if (!rawItem || typeof rawItem !== "object") return [];
    const item = rawItem as Record<string, unknown>;
    return [{
      productId: String(item.productId ?? ""),
      name: String(item.name ?? ""),
      qty: Math.max(1, Number(item.qty) || 1),
      price: Number(item.price) || 0,
      style: item.style === "hot" || item.style === "iced" ? item.style : undefined,
      addons: Array.isArray(item.addons)
        ? item.addons.flatMap((rawAddon) => {
            if (!rawAddon || typeof rawAddon !== "object") return [];
            const addon = rawAddon as Record<string, unknown>;
            return [{
              id: typeof addon.id === "string" ? addon.id : "",
              name: String(addon.name ?? ""),
              price: Number(addon.price) || 0,
              qty: Math.max(1, Number(addon.qty) || 1),
              inventoryItemId: typeof addon.inventoryItemId === "string" ? addon.inventoryItemId : undefined,
              usageAmount: addon.usageAmount != null ? Number(addon.usageAmount) : undefined,
              usageUnit: typeof addon.usageUnit === "string" ? addon.usageUnit : undefined,
            }];
          })
        : undefined,
      category: typeof item.category === "string" ? item.category : undefined,
      categoryType: typeof item.categoryType === "string" ? item.categoryType : undefined,
    }];
  });
}

function orderTimestampFromApi(value: unknown): string | null {
  if (typeof value !== "string" || !value.trim()) return null;
  return phIsoTimestamp(value) || null;
}

type PosSyncEvent = {
  eventId: string;
  tableName: string;
  recordId: string;
  operation: "upsert" | "delete";
  rowData: Record<string, unknown>;
};

// PostgREST rows are dynamically shaped by each explicit select list.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type PosSyncRow = Record<string, any>;

function eventIds(events: PosSyncEvent[], table: string, operation?: PosSyncEvent["operation"]) {
  return [...new Set(events
    .filter((event) => event.tableName === table && (!operation || event.operation === operation))
    .map((event) => event.recordId)
    .filter(Boolean))];
}

function eventParentIds(events: PosSyncEvent[], table: string, field: string) {
  return [...new Set(events
    .filter((event) => event.tableName === table)
    .map((event) => String(event.rowData[field] ?? ""))
    .filter(Boolean))];
}

function deletedEventIds(events: PosSyncEvent[], table: string, presentIds: Set<string>) {
  return [...new Set(events
    .filter((event) => event.tableName === table && event.operation === "delete")
    .map((event) => event.recordId)
    .filter((id) => id && !presentIds.has(id)))];
}

async function selectSyncRows(
  table: string,
  columns: string,
  ownerId: string,
  ids?: string[],
  idColumn = "id",
) {
  if (ids && ids.length === 0) return [];
  let query = supabaseAdmin().from(table as never).select(columns).eq("owner_id", ownerId);
  if (ids) query = query.in(idColumn, ids);
  const { data, error } = await query;
  if (error) throw new Error(`Unable to read ${table} for POS sync: ${error.message}`);
  return (data ?? []) as PosSyncRow[];
}

function mapSyncMenuItem(row: PosSyncRow, category?: PosSyncRow) {
  const categoryName = category?.name ?? "Other";
  const categoryType = normalizeMenuCategoryType(
    category?.type ?? inferMenuCategoryType(categoryName),
  );
  const legacy = parseMenuImageOptions(row.image);
  const storedStyles = Array.isArray(row.styles)
    ? row.styles.filter((style: unknown) => style === "hot" || style === "iced")
    : legacy.styles;
  const storedAddons = Array.isArray(row.addons) && row.addons.length > 0
    ? row.addons
    : legacy.addons;
  return {
    id: row.id,
    name: row.name,
    price: row.price,
    category: categoryName,
    categoryType,
    image: stripMenuImage(row.image),
    available: row.available,
    inventoryMode: row.inventory_mode === "stock_only" || row.inventory_mode === "stock_and_recipe"
      ? row.inventory_mode
      : "none",
    stockInventoryItemId: row.stock_inventory_item_id ?? undefined,
    stockUsageAmount: row.stock_usage_amount == null ? undefined : Number(row.stock_usage_amount),
    types: normalizeMenuTypeOptions({ types: row.types }),
    styles: normalizeMenuStyles({
      category: categoryName,
      categoryType,
      styles: storedStyles,
    }),
    addons: normalizeMenuAddons({ addons: storedAddons }),
  };
}

function mapSyncOrder(row: PosSyncRow, lines: PosSyncRow[]) {
  const items = lines.map((item) => {
    const category = typeof item.category_snapshot === "string"
      ? item.category_snapshot
      : undefined;
    return hydrateOrderLine({
      productId: item.product_id_snapshot ?? item.menu_item_id ?? "",
      name: item.name_snapshot ?? "",
      qty: Number(item.qty) || 0,
      price: Number(item.price_snapshot) || 0,
      category,
      categoryType: item.category_type_snapshot ?? undefined,
      style: parseDrinkStyle(item.style),
      addons: parseStoredOrderAddons(item.addons),
      serviceMode: item.service_mode === "take-out"
        ? "take-out"
        : item.service_mode === "dine-in"
          ? "dine-in"
          : undefined,
    });
  });
  const isWaste = row.payment_method === "waste" || row.record_type === "Waste";
  return {
    id: row.id,
    ownerId: row.owner_id ?? undefined,
    createdAt: row.created_at,
    baristaName: row.barista_name,
    baristaUserId: row.barista_user_id ?? undefined,
    items,
    subtotal: row.subtotal,
    discount: row.discount,
    promoLabel: row.promo_label ?? undefined,
    total: row.total,
    paymentMethod: parsePayment(row.payment_method),
    serviceMode: row.service_mode === "dine-in" || row.service_mode === "take-out"
      ? row.service_mode
      : items.find((item) => item.serviceMode)?.serviceMode,
    ticketNo: isWaste ? "" : row.ticket_no,
    recordType: isWaste ? "Waste" : row.record_type === "Purchase" ? "Purchase" : "Sale",
    paid: row.paid,
    change: row.change,
    voided: row.voided,
    voidedBy: row.voided_by ?? undefined,
    voidedByName: row.voided_by_name ?? undefined,
    voidReason: row.payment_method === "waste" ? undefined : row.void_reason ?? undefined,
    wasteReason: row.waste_reason ?? (row.payment_method === "waste" ? row.void_reason ?? undefined : undefined),
    wasteBaristas: Array.isArray(row.waste_baristas)
      ? row.waste_baristas.map(String).filter(Boolean)
      : undefined,
    isSynced: true,
  };
}

async function buildPosSyncDelta(ownerId: string, cursor: string) {
  const { data: feed, error: feedError } = await supabaseAdmin().rpc("pos_sync_read_changes", {
    p_owner_id: ownerId,
    p_after_id: cursor,
    p_limit: 1000,
  });
  if (feedError) {
    throw new Error(`Unable to read POS sync changes: ${feedError.message}`);
  }
  const result = feed as { events?: PosSyncEvent[]; cursor?: string; hasMore?: boolean } | null;
  const events = Array.isArray(result?.events) ? result.events : [];
  const delta: PosSyncRow = {
    ok: true,
    mode: "delta",
    timestamp: new Date().toISOString(),
    cursor: result?.cursor ?? cursor,
    hasMore: result?.hasMore === true,
    deleted: {},
  };
  if (events.length === 0) return delta;

  const changedTables = new Set(events.map((event) => event.tableName));
  const addDeleted = (key: string, ids: string[]) => {
    if (ids.length > 0) delta.deleted[key] = ids;
  };

  if (changedTables.has("pos_state")) {
    const [row] = await selectSyncRows(
      "pos_state",
      "id,is_open,opened_at,opened_by,opened_by_name,inventory_features_enabled,print_button_hidden,cash_drawer_opening_float,attendance_auth_mode",
      ownerId,
    );
    if (row) {
      delta.pos = {
        isOpen: Boolean(row.is_open),
        openedAt: row.opened_at,
        openedBy: row.opened_by_name ?? row.opened_by,
        inventoryFeaturesEnabled: row.inventory_features_enabled !== false,
        printButtonHidden: row.print_button_hidden === true,
        cashDrawerOpeningFloat: Number(row.cash_drawer_opening_float) || 0,
        attendanceAuthMode: row.attendance_auth_mode ?? "username_password",
      };
    } else {
      delta.pos = {
        isOpen: false,
        openedAt: null,
        openedBy: null,
        inventoryFeaturesEnabled: false,
        printButtonHidden: false,
        cashDrawerOpeningFloat: 0,
        attendanceAuthMode: "username_password",
      };
    }
  }

  if (changedTables.has("menu_categories")) {
    const rows = await selectSyncRows("menu_categories", "id,name,type", ownerId);
    delta.categories = rows.map((row) => row.name);
    delta.categoryTypes = Object.fromEntries(rows.map((row) => [
      String(row.name ?? "").trim(),
      normalizeMenuCategoryType(row.type ?? inferMenuCategoryType(String(row.name ?? ""))),
    ]));
  }

  if (changedTables.has("menu_items")) {
    const ids = eventIds(events, "menu_items", "upsert");
    const rows = await selectSyncRows(
      "menu_items",
      "id,name,price,category_id,image,available,inventory_mode,stock_inventory_item_id,stock_usage_amount,types,styles,addons",
      ownerId,
      ids,
    );
    const categoryIds = [...new Set(rows.map((row) => row.category_id).filter(Boolean))];
    const categories = await selectSyncRows("menu_categories", "id,name,type", ownerId, categoryIds);
    const categoriesById = new Map(categories.map((row) => [row.id, row]));
    delta.menu = rows.map((row) => mapSyncMenuItem(row, categoriesById.get(row.category_id)));
    addDeleted("menu", deletedEventIds(events, "menu_items", new Set(rows.map((row) => row.id))));
  }

  if (changedTables.has("inventory_items")) {
    const ids = eventIds(events, "inventory_items", "upsert");
    const rows = await selectSyncRows(
      "inventory_items",
      "id,name,unit,cost,stock,max_stock,reorder_threshold,opening_stock,purchase_unit_size,cup_usage_amount,cups_make,inventory_type,cup_size",
      ownerId,
      ids,
    );
    delta.inventory = rows.map((row) => ({
      id: row.id,
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
      inventoryType: typeof row.inventory_type === "string" && row.inventory_type.trim()
        ? row.inventory_type.trim()
        : undefined,
      cupSize: typeof row.cup_size === "string" && row.cup_size.trim() ? row.cup_size.trim() : undefined,
    }));
    addDeleted("inventory", deletedEventIds(events, "inventory_items", new Set(rows.map((row) => row.id))));
  }

  const affectedOrderIds = new Set([
    ...eventIds(events, "orders"),
    ...eventParentIds(events, "order_items", "order_id"),
  ]);
  if (affectedOrderIds.size > 0) {
    const ids = [...affectedOrderIds];
    const orderRows = await selectSyncRows(
      "orders",
      "id,owner_id,created_at,barista_name,barista_user_id,subtotal,discount,promo_label,total,payment_method,ticket_no,paid,change,voided,voided_by,voided_by_name,void_reason,waste_reason,waste_baristas,deleted_at,record_type,service_mode",
      ownerId,
      ids,
    );
    const lineRows = await selectSyncRows(
      "order_items",
      "id,order_id,menu_item_id,product_id_snapshot,name_snapshot,category_snapshot,category_type_snapshot,qty,price_snapshot,style,addons,service_mode",
      ownerId,
      ids,
      "order_id",
    );
    const linesByOrder = new Map<string, PosSyncRow[]>();
    for (const line of lineRows) {
      const current = linesByOrder.get(line.order_id) ?? [];
      current.push(line);
      linesByOrder.set(line.order_id, current);
    }
    const activeOrders = orderRows.filter((row) => !row.deleted_at);
    delta.orders = activeOrders.map((row) => mapSyncOrder(row, linesByOrder.get(row.id) ?? []));
    const presentOrders = new Set(activeOrders.map((row) => row.id));
    addDeleted("orders", [
      ...deletedEventIds(events, "orders", presentOrders),
      ...orderRows.filter((row) => row.deleted_at).map((row) => row.id),
    ].filter((id, index, list) => list.indexOf(id) === index));
  }

  if (changedTables.has("restocks")) {
    const rows = await selectSyncRows(
      "restocks",
      "id,inventory_item_id,item_name_snapshot,quantity_added,purchase_qty,purchase_unit,unit_cost,created_at",
      ownerId,
      eventIds(events, "restocks", "upsert"),
    );
    delta.restocks = rows.map((row) => ({
      id: row.id,
      inventoryItemId: row.inventory_item_id ?? undefined,
      itemName: row.item_name_snapshot,
      quantityAdded: Number(row.quantity_added),
      purchaseQty: row.purchase_qty == null ? undefined : Number(row.purchase_qty),
      purchaseUnit: row.purchase_unit ?? undefined,
      unitCost: row.unit_cost == null ? undefined : Number(row.unit_cost),
      date: row.created_at,
      isSynced: true,
    }));
    addDeleted("restocks", deletedEventIds(events, "restocks", new Set(rows.map((row) => row.id))));
  }

  if (changedTables.has("usage_logs")) {
    const rows = await selectSyncRows(
      "usage_logs",
      "id,order_id,order_item_id,inventory_item_id,item_name_snapshot,used_amount,unit,created_at",
      ownerId,
      eventIds(events, "usage_logs", "upsert"),
    );
    delta.usageLogs = rows.map((row) => ({
      id: row.id,
      orderId: row.order_id ?? "",
      orderItemId: row.order_item_id ?? "",
      inventoryItemId: row.inventory_item_id ?? undefined,
      date: row.created_at,
      itemName: row.item_name_snapshot,
      usedAmount: Number(row.used_amount),
      unit: row.unit,
    }));
    addDeleted("usageLogs", deletedEventIds(events, "usage_logs", new Set(rows.map((row) => row.id))));
  }

  if (changedTables.has("recipes")) {
    const menuIds = [...new Set(events
      .filter((event) => event.tableName === "recipes")
      .map((event) => String(event.rowData.menu_item_id ?? ""))
      .filter(Boolean))];
    const rows = await selectSyncRows(
      "recipes",
      "id,menu_item_id,inventory_item_id,amount,unit",
      ownerId,
      menuIds,
      "menu_item_id",
    );
    const grouped: Record<string, Record<string, unknown>[]> = Object.fromEntries(menuIds.map((id) => [id, []]));
    for (const row of rows) {
      grouped[row.menu_item_id].push({
        inventoryItemId: row.inventory_item_id,
        name: "",
        amount: Number(row.amount),
        unit: row.unit,
      });
    }
    delta.recipes = grouped;
  }

  const costingIds = new Set([
    ...eventIds(events, "recipe_costings"),
    ...eventParentIds(events, "recipe_costing_menu_items", "recipe_costing_id"),
    ...eventParentIds(events, "recipe_costing_ingredients", "recipe_costing_id"),
  ]);
  if (costingIds.size > 0) {
    const ids = [...costingIds];
    const parents = await selectSyncRows(
      "recipe_costings",
      "id,name,hot_cup_inventory_item_id,iced_cup_inventory_item_id,other_cup_inventory_item_id,extra_cup_inventory_item_ids,cup_recipes",
      ownerId,
      ids,
    );
    const menus = await selectSyncRows(
      "recipe_costing_menu_items",
      "id,recipe_costing_id,menu_item_name",
      ownerId,
      ids,
      "recipe_costing_id",
    );
    const ingredients = await selectSyncRows(
      "recipe_costing_ingredients",
      "id,recipe_costing_id,inventory_item_id,name,amount,unit",
      ownerId,
      ids,
      "recipe_costing_id",
    );
    delta.recipeCostings = parents.map((row) => ({
      id: row.id,
      name: row.name,
      menuItems: menus.filter((item) => item.recipe_costing_id === row.id).map((item) => item.menu_item_name),
      ingredients: ingredients.filter((item) => item.recipe_costing_id === row.id).map((item) => ({
        inventoryItemId: item.inventory_item_id ?? (item.name ? "other" : ""),
        name: item.name,
        amount: Number(item.amount),
        unit: item.unit,
      })),
      hotCupInventoryItemId: row.hot_cup_inventory_item_id ?? undefined,
      icedCupInventoryItemId: row.iced_cup_inventory_item_id ?? undefined,
      otherCupInventoryItemId: row.other_cup_inventory_item_id ?? undefined,
      extraCupInventoryItemIds: Array.isArray(row.extra_cup_inventory_item_ids)
        ? row.extra_cup_inventory_item_ids.filter((id: unknown) => typeof id === "string" && id.trim())
        : [],
      cupRecipes: row.cup_recipes && typeof row.cup_recipes === "object" && !Array.isArray(row.cup_recipes)
        ? row.cup_recipes
        : {},
    }));
    addDeleted("recipeCostings", deletedEventIds(events, "recipe_costings", new Set(parents.map((row) => row.id))));
  }

  if (changedTables.has("void_requests")) {
    const rows = await selectSyncRows(
      "void_requests",
      "id,requested_at,requested_by_id,requested_by_name,reason,status,order_id,items,subtotal,discount,promo_label,total,payment_method,approved_at,approved_by_name,processed_order_id",
      ownerId,
      eventIds(events, "void_requests", "upsert"),
    );
    delta.voidRequests = rows.map((row) => ({
      id: row.id,
      requestedAt: row.requested_at,
      requestedById: row.requested_by_id ?? row.id,
      requestedByName: row.requested_by_name,
      reason: row.reason,
      status: row.status,
      orderId: row.order_id ?? undefined,
      items: Array.isArray(row.items) ? row.items : [],
      subtotal: Number(row.subtotal),
      discount: Number(row.discount),
      promoLabel: row.promo_label ?? undefined,
      total: Number(row.total),
      paymentMethod: parsePayment(row.payment_method),
      approvedAt: row.approved_at ?? undefined,
      approvedByName: row.approved_by_name ?? undefined,
      processedOrderId: row.processed_order_id ?? undefined,
      isSynced: true,
    }));
    addDeleted("voidRequests", deletedEventIds(events, "void_requests", new Set(rows.map((row) => row.id))));
  }

  if (changedTables.has("login_activity")) {
    const rows = await selectSyncRows(
      "login_activity",
      "id,user_id,username,name,role,type,at,photo_path",
      ownerId,
      eventIds(events, "login_activity", "upsert"),
    );
    delta.loginActivity = rows.map((row) => ({
      id: row.id,
      userId: row.user_id ?? row.id,
      username: row.username,
      name: row.name,
      role: row.role,
      type: row.type,
      at: row.at,
      photoPath: row.photo_path ?? undefined,
      isSynced: true,
    }));
    addDeleted("loginActivity", deletedEventIds(events, "login_activity", new Set(rows.map((row) => row.id))));
  }

  const userIds = new Set([
    ...eventIds(events, "staff_users"),
    ...(changedTables.has("promotions") ? [ownerId] : []),
  ]);
  if (userIds.size > 0) {
    const users = await selectSyncRows(
      "staff_users",
      "id,owner_id,username,email,password_changed,name,role,title,permissions,avatar_path",
      ownerId,
      [...userIds],
    );
    const { data: promoRows, error: promoError } = await supabaseAdmin()
      .from("promotions")
      .select("owner_id,code,discount_type,discount_value,expires_at,redeemed_at,redeemed_order_id")
      .eq("owner_id", ownerId);
    if (promoError) throw new Error(`Unable to read POS promotions: ${promoError.message}`);
    delta.users = users.map((user) => {
      const role = parseRole(String(user.title ?? ""), user.role);
      const permissions = {
        ...(user.permissions ?? {}),
        promoCodes: ((promoRows ?? []) as PosSyncRow[])
          .filter((promo) => promo.owner_id === user.id)
          .map((promo) => ({
            code: promo.code,
            discountType: promo.discount_type,
            discountValue: Number(promo.discount_value),
            expiresAt: promo.expires_at ?? undefined,
            redeemedAt: promo.redeemed_at ?? undefined,
            redeemedOrderId: promo.redeemed_order_id ?? undefined,
          })),
      };
      return {
        id: user.id,
        username: user.username,
        email: user.email ?? "",
        name: user.name,
        passwordChanged: Boolean(user.password_changed),
        avatarPath: user.avatar_path ?? undefined,
        permissions,
        role,
        title: user.title || (role === "admin" || role === "cashier" ? "Owner" : "Barista"),
      };
    });
    addDeleted("users", deletedEventIds(events, "staff_users", new Set(users.map((row) => row.id))));
  }

  return delta;
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: corsHeaders });
}

export async function GET(request: NextRequest) {
  const claims = readPosApiToken(request.headers.get("authorization"));
  if (!claims) {
    return NextResponse.json(
      { ok: false, error: "POS session expired. Sign in again." },
      { status: 401, headers: corsHeaders },
    );
  }
  if (claims.role === "barista") {
    return NextResponse.json(
      { ok: false, error: "This account cannot access the POS store." },
      { status: 403, headers: corsHeaders },
    );
  }

  try {
    const posOwnerId = claims.role === "cashier" ? claims.userId : await legacyOwnerId();
    if (!posOwnerId) {
      throw new Error("Unable to resolve the POS store owner for incremental sync.");
    }
    const syncOwnerId = posOwnerId;
    const requestedCursor = request.nextUrl.searchParams.get("cursor");
    if (requestedCursor !== null && !/^\d+$/.test(requestedCursor)) {
      return NextResponse.json(
        { ok: false, error: "Invalid POS sync cursor." },
        { status: 400, headers: corsHeaders },
      );
    }

    if (requestedCursor !== null) {
      if (claims.role === "cashier") {
        const { data: cashier, error: cashierError } = await supabaseAdmin()
          .from("staff_users")
          .select("password_changed")
          .eq("id", claims.userId)
          .maybeSingle();
        if (cashierError) throw new Error(`Unable to verify Owner account: ${cashierError.message}`);
        if (!cashier?.password_changed) {
          return NextResponse.json(
            { ok: false, error: "Change your Owner password before using the POS." },
            { status: 403, headers: corsHeaders },
          );
        }
      }
      return NextResponse.json(
        await buildPosSyncDelta(syncOwnerId, requestedCursor),
        { headers: corsHeaders },
      );
    }

    const { data: bootstrapCursor, error: cursorError } = await supabaseAdmin()
      .rpc("pos_sync_current_cursor", { p_owner_id: syncOwnerId });
    if (cursorError) {
      throw new Error(`Unable to establish POS bootstrap cursor: ${cursorError.message}`);
    }
    const store = await getFreshStore({ ownerId: posOwnerId });
    const ownerAccount = posOwnerId
      ? (await getOwnerAccounts()).find((user) => user.id === posOwnerId)
      : undefined;
    if (claims.role === "cashier") {
      const cashier = ownerAccount ?? store.users.find((user) => user.id === claims.userId);
      if (!cashier?.passwordChanged) {
        return NextResponse.json(
          { ok: false, error: "Change your Owner password before using the POS." },
          { status: 403, headers: corsHeaders },
        );
      }
    }
    return NextResponse.json(
      {
        ok: true,
        mode: "bootstrap",
        cursor: String(bootstrapCursor ?? "0"),
        timestamp: new Date().toISOString(),
        pos: store.pos,
        menu: store.menu.map((item) => ({
          ...item,
          styles: normalizeMenuStyles(item),
          addons: normalizeMenuAddons(item),
        })),
        categories: store.categories,
        categoryTypes: store.categoryTypes,
        inventory: store.inventory,
        orders: store.orders,
        restocks: store.restocks,
        usageLogs: store.usageLogs,
        recipes: store.recipes,
        recipeCostings: store.recipeCostings,
        voidRequests: store.voidRequests,
        loginActivity: store.loginActivity,
        users: [
          ...store.users.filter((user) => user.id !== ownerAccount?.id),
          ...(ownerAccount ? [ownerAccount] : []),
        ].map((u) => {
          const resolvedRole = parseRole(String(u.title ?? ""), u.role);
          return {
            id: u.id,
            username: u.username,
            email: u.email,
            name: u.name,
            avatarPath: u.avatarPath,
            passwordChanged: Boolean(u.passwordChanged),
            permissions: u.permissions ?? {
              stockInventory: true,
              restockInventory: true,
              connectLabels: true,
              connectslip: true,
              printButton: true,
              internalslip: true,
              cupLabels: true,
              dineIn: true,
              takeOut: true,
              promotionDiscount: false,
              promotionsEnabled: false,
              promoCodes: [],
            },
            role: resolvedRole,
            title:
              u.title ||
              (resolvedRole === "admin"
                ? "Owner"
                : resolvedRole === "cashier"
                    ? "Owner"
                    : "Barista"),
          };
        }),
      },
      { headers: corsHeaders },
    );
  } catch (error) {
    return NextResponse.json(
      {
        ok: false,
        error: error instanceof Error ? error.message : "Failed to load centralized store",
      },
      { status: 500, headers: corsHeaders },
    );
  }
}

export async function POST(req: NextRequest): Promise<NextResponse> {
  try {
    const body = await req.json();
    const action = String(body?.action ?? "").trim();
    if (["delete_void_request", "approve_void_request"].includes(action)) {
      return NextResponse.json(
        { ok: false, error: "Voiding is disabled." },
        { status: 410, headers: corsHeaders },
      );
    }

    if (action === "change_cashier_password") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const password = String(body.password ?? "");
      const newPassword = String(body.newPassword ?? "");
      if (!email || !password || newPassword.length < 8) {
        return NextResponse.json(
          { ok: false, error: "Enter your Owner username or email, current password, and a new password with at least 8 characters." },
          { status: 400, headers: corsHeaders },
        );
      }

      const store = await getFreshStore({ ownerId: null });
      const user = store.users.find(
        (entry) =>
          entry.role === "cashier" &&
          (entry.email?.trim().toLowerCase() === email ||
            entry.username.trim().toLowerCase() === email),
      );
      const currentPasswordMatches = user?.password
        ? user.password.startsWith("$2")
          ? await bcrypt.compare(password, user.password)
          : user.password === password || user.password.trim() === password.trim()
        : false;
      if (
        !user ||
        user.passwordChanged ||
        !currentPasswordMatches
      ) {
        return NextResponse.json(
          { ok: false, error: "Those details do not match an Owner account that needs a password change." },
          { status: 401, headers: corsHeaders },
        );
      }

      const updatedUser = {
        ...user,
        password: await bcrypt.hash(newPassword, 12),
        passwordChanged: true,
      };
      await upsertStaffUserRecord(updatedUser);
      return NextResponse.json(
        {
          ok: true,
          token: createPosApiToken({
            userId: updatedUser.id,
            username: updatedUser.username,
            name: updatedUser.name,
            role: "cashier",
          }),
          user: {
            id: updatedUser.id,
            username: updatedUser.username,
            email: updatedUser.email,
            name: updatedUser.name,
            passwordChanged: true,
            role: "cashier",
            title: updatedUser.title || "Owner",
          },
        },
        { headers: corsHeaders },
      );
    }

    if (action === "new_owner_login") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const username = String(body.username ?? "").trim().toLowerCase();
      const password = String(body.password ?? "");
      if (
        !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
        !username ||
        !password ||
        body.legalAccepted !== true
      ) {
        return NextResponse.json(
          { ok: false, error: "Enter valid Owner details and accept the Terms of Use and Privacy Policy." },
          { status: 400, headers: corsHeaders },
        );
      }

      const store = await getFreshStore({ ownerId: null });
      const user = store.users.find(
        (entry) => entry.role === "cashier" && entry.username.trim().toLowerCase() === username,
      );
      const passwordMatches = user?.password
        ? user.password.startsWith("$2")
          ? await bcrypt.compare(password, user.password)
          : user.password === password || user.password.trim() === password.trim()
        : false;
      if (!user || !passwordMatches) {
        return NextResponse.json(
          { ok: false, error: "The Owner username or password is incorrect." },
          { status: 401, headers: corsHeaders },
        );
      }

      const emailInUse = store.users.some(
        (entry) => entry.id !== user.id && entry.email?.trim().toLowerCase() === email,
      );
      if (emailInUse) {
        return NextResponse.json(
          { ok: false, error: "That email is already assigned to another account." },
          { status: 409, headers: corsHeaders },
        );
      }
      if (user.email?.trim() && user.email.trim().toLowerCase() !== email) {
        return NextResponse.json(
          { ok: false, error: "This Owner account is already linked to a different email." },
          { status: 409, headers: corsHeaders },
        );
      }

      const updatedUser = {
        ...user,
        email: user.email?.trim() ? user.email : email,
        agreedToTerms: true,
        agreedAt: new Date().toISOString(),
      };
      await withStoreTenant(user.id, () =>
        upsertStaffUserRecord({ ...updatedUser, ownerId: user.id }),
      );
      if (!updatedUser.passwordChanged) {
        return NextResponse.json(
          { ok: true, requiresPasswordChange: true },
          { headers: corsHeaders },
        );
      }

      return NextResponse.json(
        {
          ok: true,
          token: createPosApiToken({
            userId: updatedUser.id,
            username: updatedUser.username,
            name: updatedUser.name,
            role: "cashier",
          }),
          user: {
            id: updatedUser.id,
            username: updatedUser.username,
            email: updatedUser.email,
            name: updatedUser.name,
            passwordChanged: true,
            role: "cashier",
            title: updatedUser.title || "Owner",
          },
        },
        { headers: corsHeaders },
      );
    }

    if (action === "auth") {
      const username = String(body.username ?? "").trim().toLowerCase();
      const email = String(body.email ?? "").trim().toLowerCase();
      const password = String(body.password ?? "");
      if ((!username && !email) || !password) {
        return NextResponse.json(
          { ok: false, error: "Enter your Owner username or email and password." },
          { status: 400, headers: corsHeaders },
        );
      }

      const store = await getFreshStore({ ownerId: null });
      const identifier = username || email;
      const user = store.users.find(
        (u) =>
          ["cashier", "admin", "barista", "pos_cashier"].includes(u.role) &&
          (u.username.trim().toLowerCase() === identifier ||
            u.name.trim().toLowerCase() === identifier ||
            Boolean(u.email && u.email.trim().toLowerCase() === identifier)),
      );
      if (!user || !user.password) {
        console.warn("POS staff authentication rejected: staff account unavailable.");
        return NextResponse.json(
          { ok: false, error: "Invalid email or password" },
          { status: 401, headers: corsHeaders },
        );
      }

      const validPassword = user.password.startsWith("$2")
        ? await bcrypt.compare(password, user.password)
        : user.password === password || user.password.trim() === password.trim();

      if (!validPassword) {
        console.warn("POS staff authentication rejected: password mismatch.");
        return NextResponse.json(
          { ok: false, error: "Invalid email or password" },
          { status: 401, headers: corsHeaders },
        );
      }

      const resolvedRole = parseRole(String(user.title ?? ""), user.role);
      if (resolvedRole === "cashier" && !user.passwordChanged) {
        return NextResponse.json(
          { ok: true, requiresPasswordChange: true },
          { headers: corsHeaders },
        );
      }
      return NextResponse.json(
        {
          ok: true,
          token: createPosApiToken({
            userId: user.id,
            username: user.username,
            name: user.name,
            role: resolvedRole,
          }),
          user: {
            id: user.id,
            username: user.username,
            email: user.email,
            name: user.name,
            passwordChanged: Boolean(user.passwordChanged),
            role: resolvedRole,
            title: user.title || (resolvedRole === "admin" ? "Admin" : resolvedRole === "cashier" ? "Owner" : "Barista"),
          },
        },
        { headers: corsHeaders },
      );
    }

    const claims = readPosApiToken(req.headers.get("authorization"));
    if (!claims) {
      return NextResponse.json(
        { ok: false, error: "POS session expired. Sign in again." },
        { status: 401, headers: corsHeaders },
      );
    }

    if (action === "delete_owner_account") {
      if (claims.role !== "cashier") {
        return NextResponse.json(
          { ok: false, error: "Only the Owner can delete this account." },
          { status: 403, headers: corsHeaders },
        );
      }
      const password = String(body.password ?? "");
      if (body.confirmation !== "DELETE MY ACCOUNT" || !password) {
        return NextResponse.json(
          { ok: false, error: "Confirm the deletion phrase and enter your current password." },
          { status: 400, headers: corsHeaders },
        );
      }

      const { data: owner, error: ownerLookupError } = await supabaseAdmin()
        .from("staff_users")
        .select("id, owner_id, role, password")
        .eq("id", claims.userId)
        .maybeSingle();
      if (ownerLookupError || !owner || owner.role !== "cashier" || (owner.owner_id && owner.owner_id !== claims.userId)) {
        return NextResponse.json(
          { ok: false, error: "Owner account could not be verified." },
          { status: 404, headers: corsHeaders },
        );
      }
      const passwordMatches = owner.password
        ? owner.password.startsWith("$2")
          ? await bcrypt.compare(password, owner.password)
          : owner.password === password || owner.password.trim() === password.trim()
        : false;
      if (!passwordMatches) {
        return NextResponse.json(
          { ok: false, error: "Your current password is incorrect." },
          { status: 401, headers: corsHeaders },
        );
      }

      await deleteOwnerAccountAndData(claims.userId);
      return NextResponse.json(
        { ok: true, message: "Owner account and store data were permanently deleted." },
        { headers: corsHeaders },
      );
    }

    const tenantId = claims.role === "cashier"
      ? claims.userId
      : claims.role === "barista" || claims.role === "pos_cashier"
        ? await ownerIdForStaff(claims.userId)
        : await legacyOwnerId();
    if (!tenantId) {
      return NextResponse.json({ ok: false, error: "This account is not assigned to an Owner store." }, { status: 403, headers: corsHeaders });
    }
    if (action === "sync_batch") {
      if (!Array.isArray(body.operations) || body.operations.length > 100) {
        return NextResponse.json(
          { ok: false, error: "A sync batch must contain between 1 and 100 operations." },
          { status: 400, headers: corsHeaders },
        );
      }

      const allowedActions = new Set([
        "create_order",
        "void_checkout",
        "void_order",
        "create_restock",
        "delete_restock",
        "upsert_inventory_item",
        "delete_inventory_item",
        "login_activity",
        "create_void_request",
      ]);
      const results = [];
      for (const operation of body.operations) {
        if (!operation || typeof operation !== "object" || Array.isArray(operation)) {
          results.push({ ok: false, error: "Invalid batch operation." });
          continue;
        }
        const operationBody = operation as Record<string, unknown>;
        const operationAction = String(operationBody.action ?? "");
        if (!allowedActions.has(operationAction)) {
          results.push({ ok: false, error: `Unsupported batch operation: ${operationAction || "unknown"}.` });
          continue;
        }
        const nestedRequest = new NextRequest(req.url, {
          method: "POST",
          headers: {
            authorization: req.headers.get("authorization") ?? "",
            "content-type": "application/json",
          },
          body: JSON.stringify(operationBody),
        });
        const nestedResponse: NextResponse = await POST(nestedRequest);
        const result = await nestedResponse.json() as Record<string, unknown>;
        results.push({
          ...result,
          ok: nestedResponse.ok && result.ok === true,
          action: operationAction,
        });
      }
      return NextResponse.json({ ok: true, results }, { headers: corsHeaders });
    }
    if (action === "get_staff_avatar_url") {
      if (!["cashier", "admin", "pos_cashier"].includes(claims.role)) {
        return NextResponse.json(
          { ok: false, error: "This account cannot view staff photos." },
          { status: 403, headers: corsHeaders },
        );
      }
      const staffUserId = typeof body.staffUserId === "string"
        ? body.staffUserId.trim()
        : "";
      if (!staffUserId) {
        return NextResponse.json(
          { ok: false, error: "Select a valid staff account." },
          { status: 400, headers: corsHeaders },
        );
      }
      const { data: staff, error: staffError } = await supabaseAdmin()
        .from("staff_users")
        .select("id,owner_id,avatar_path")
        .eq("id", staffUserId)
        .eq("owner_id", tenantId)
        .maybeSingle();
      if (staffError) {
        throw new Error(`Unable to load staff photo details: ${staffError.message}`);
      }
      if (!staff) {
        return NextResponse.json(
          { ok: false, error: "Staff account not found in your workspace." },
          { status: 404, headers: corsHeaders },
        );
      }
      if (!staff.avatar_path) {
        return NextResponse.json({ ok: true, signedUrl: null }, { headers: corsHeaders });
      }
      const { data, error } = await supabaseAdmin()
        .storage
        .from("staff-avatars")
        .createSignedUrl(staff.avatar_path, 15 * 60);
      if (error || !data?.signedUrl) {
        throw new Error(`Unable to open staff photo: ${error?.message ?? "No secure link was returned."}`);
      }
      return NextResponse.json(
        { ok: true, signedUrl: data.signedUrl },
        { headers: corsHeaders },
      );
    }
    return await withStoreTenant(tenantId, async () => {
    if ((claims.role === "barista" || claims.role === "pos_cashier") && action !== "barista_shift_activity") {
      return NextResponse.json(
        { ok: false, error: "This account cannot perform POS actions." },
        { status: 403, headers: corsHeaders },
      );
    }
    if (claims.role === "cashier") {
      const store = await getFreshStore();
      const cashier = store.users.find((user) => user.id === claims.userId);
      if (!cashier?.passwordChanged) {
        return NextResponse.json(
          { ok: false, error: "Change your Owner password before using the POS." },
          { status: 403, headers: corsHeaders },
        );
      }
    }

    if (action === "validate_promotion") {
      const code = String(body.code ?? "").replace(/\s+/g, "").toUpperCase();
      if (!/^(?:[A-Z0-9]{6}|[A-Z0-9]{1,16}-[A-Z0-9]{6})$/.test(code)) {
        return NextResponse.json(
          { ok: false, error: "Enter a valid promotion voucher." },
          { status: 400, headers: corsHeaders },
        );
      }

      const promotionOwner = (await getOwnerAccounts()).find(
        (entry) => entry.id === tenantId,
      );
      const promotionPermissions = promotionOwner?.permissions;
      if (
        !promotionPermissions ||
        promotionPermissions.promotionsEnabled !== true ||
        promotionPermissions.promotionDiscount !== true
      ) {
        return NextResponse.json(
          { ok: false, error: "Promotions are not enabled for this Owner." },
          { status: 403, headers: corsHeaders },
        );
      }
      const promotion = promotionPermissions.promoCodes?.find(
        (entry) => entry.code.trim().toUpperCase() === code,
      );
      if (!promotion) {
        return NextResponse.json(
          { ok: false, error: "Invalid promotion voucher." },
          { status: 404, headers: corsHeaders },
        );
      }
      if (promotion.redeemedAt) {
        return NextResponse.json(
          { ok: false, error: "Promotion voucher already used." },
          { status: 409, headers: corsHeaders },
        );
      }
      if (promotion.expiresAt && Date.parse(promotion.expiresAt) <= Date.now()) {
        return NextResponse.json(
          { ok: false, error: "Promotion voucher has expired." },
          { status: 409, headers: corsHeaders },
        );
      }
      return NextResponse.json(
        {
          ok: true,
          promotion: {
            code: promotion.code,
            discountType: promotion.discountType,
            discountValue: promotion.discountValue,
            expiresAt: promotion.expiresAt ?? null,
          },
        },
        { headers: corsHeaders },
      );
    }

    if (action === "create_order") {
      const rawOrder = body.order ?? {};
      if (!claims || !["cashier", "admin"].includes(claims.role)) {
        return NextResponse.json({ ok: false, error: "Owner access required." }, { status: 403, headers: corsHeaders });
      }
      if (rawOrder.voided) {
        return NextResponse.json(
          { ok: false, error: "Use the authenticated void checkout action." },
          { status: 400, headers: corsHeaders },
        );
      }
      const createdAt = orderTimestampFromApi(rawOrder.createdAt);
      if (!createdAt) {
        return NextResponse.json(
          { ok: false, error: "A valid device order timestamp is required." },
          { status: 400, headers: corsHeaders },
        );
      }
      const store = await getFreshStore({ ownerId: claims.role === "cashier" ? claims.userId : undefined });
      const ownerAccount = (await getOwnerAccounts()).find((user) => user.id === tenantId);
      const existingOrder = store.orders.find((o) => o.id === rawOrder.id);
      if (existingOrder) {
        return NextResponse.json(
          { ok: true, ticketNo: existingOrder.ticketNo ?? rawOrder.ticketNo ?? "", order: existingOrder },
          { headers: corsHeaders },
        );
      }

      const serviceMode: NonNullable<OrderItem["serviceMode"]> =
        rawOrder.serviceMode === "take-out" ? "take-out" : "dine-in";
      const orderItems: OrderItem[] = orderItemsFromApi(rawOrder.items).map(
        (item): OrderItem => ({
          ...item,
          category: item.category ?? store.menu.find((menuItem) => menuItem.id === item.productId)?.category,
          categoryType: item.categoryType ??
            store.menu.find((menuItem) => menuItem.id === item.productId)?.categoryType,
          serviceMode,
        }),
      );
      const requestedPromoCode = typeof rawOrder.promoLabel === "string"
        ? rawOrder.promoLabel.replace(/\s+/g, "").toUpperCase()
        : "";
      const requestedDiscount = Math.round(Number(rawOrder.discount) || 0);
      if (requestedPromoCode || requestedDiscount > 0) {
        if (!/^(?:[A-Z0-9]{6}|[A-Z0-9]{1,16}-[A-Z0-9]{6})$/.test(requestedPromoCode)) {
          return NextResponse.json({ ok: false, error: "Invalid promotion code." }, { status: 400, headers: corsHeaders });
        }
        const owner = ownerAccount ?? store.users.find((user) => user.id === claims.userId && user.role === "cashier");
        const permissions = owner?.permissions;
        const promo = Array.isArray(permissions?.promoCodes)
          ? permissions.promoCodes.find((entry) => entry.code.trim().toUpperCase() === requestedPromoCode)
          : undefined;
        if (!owner || permissions?.promotionsEnabled !== true || permissions.promotionDiscount !== true || !promo) {
          return NextResponse.json({ ok: false, error: "Invalid promotion code." }, { status: 400, headers: corsHeaders });
        }
        if (promo.redeemedAt) {
          return NextResponse.json({ ok: false, error: "The promotion code already used." }, { status: 409, headers: corsHeaders });
        }
        if (promo.expiresAt && Date.parse(promo.expiresAt) <= Date.now()) {
          return NextResponse.json({ ok: false, error: "This promo voucher has expired." }, { status: 409, headers: corsHeaders });
        }
        const subtotal = Number(rawOrder.subtotal) || 0;
        const promoItemIndex = typeof rawOrder.promoItemIndex === "number" && Number.isInteger(rawOrder.promoItemIndex)
          ? rawOrder.promoItemIndex
          : null;
        const promoItemQty = typeof rawOrder.promoItemQty === "number" && Number.isInteger(rawOrder.promoItemQty)
          ? rawOrder.promoItemQty
          : 1;
        const selectedItem = promoItemIndex != null ? orderItems[promoItemIndex] : undefined;
        const freeItemQty = Math.max(1, Math.floor(promo.discountValue || 1));
        const rawExpectedDiscount = promo.discountType === "item"
          ? selectedItem && promoItemQty === freeItemQty && promoItemQty <= selectedItem.qty
            ? (selectedItem.price + (selectedItem.addons ?? []).reduce((sum, addon) => sum + addon.price * addon.qty, 0)) * freeItemQty
            : -1
          : promo.discountType === "amount"
            ? promo.discountValue
            : subtotal * promo.discountValue / 100;
        const expectedDiscount = promo.discountType === "item"
          ? Math.round(rawExpectedDiscount)
          : Math.min(subtotal, Math.round(rawExpectedDiscount));
        if (requestedDiscount !== expectedDiscount) {
          return NextResponse.json({ ok: false, error: "Promotion discount does not match this code." }, { status: 400, headers: corsHeaders });
        }
      }
      const isWasteOrder = String(rawOrder.paymentMethod ?? "").trim().toLowerCase() === "waste" ||
        String(rawOrder.recordType ?? "").trim().toLowerCase() === "waste" ||
        String(rawOrder.id ?? "").trim().toLowerCase().startsWith("waste-") ||
        Boolean(rawOrder.wasteReason);
      const wastePermissionOwner = ownerAccount ?? store.users.find(
        (user) => user.id === tenantId && user.role === "cashier",
      );
      if (isWasteOrder && wastePermissionOwner?.permissions?.wasteManagement === false) {
        return NextResponse.json(
          { ok: false, error: "Waste recording is disabled for this POS." },
          { status: 403, headers: corsHeaders },
        );
      }
      const requestedCashierId = String(rawOrder.baristaUserId ?? '').trim();
      const requestedCashier = store.users.find((user) => {
        if (user.id !== requestedCashierId) return false;
        const role = parseRole(String(user.title ?? ''), user.role);
        return isWasteOrder
          ? role === "pos_cashier"
          : ["cashier", "admin"].includes(role);
      });
      const cashierShift = isWasteOrder
        ? pairLoginSessions(store.loginActivity ?? []).find((shift) =>
            shift.role === "pos_cashier" &&
            Boolean(shift.loginAt) &&
            shift.loginAt! <= createdAt &&
            (!shift.logoutAt || shift.logoutAt >= createdAt),
          )
        : undefined;
      const wasteCashier = isWasteOrder
        ? requestedCashier ?? store.users.find(
            (user) => user.id === cashierShift?.userId && user.role === "pos_cashier",
          )
        : undefined;
      const wasteReason = typeof rawOrder.wasteReason === "string" && rawOrder.wasteReason.trim()
        ? rawOrder.wasteReason.trim()
        : isWasteOrder && typeof rawOrder.voidReason === "string" && rawOrder.voidReason.trim()
          ? rawOrder.voidReason.trim()
          : undefined;
      const order: Order = {
        id: String(rawOrder.id || (isWasteOrder ? `waste-${Date.now()}` : `ord-${Date.now()}`)),
        createdAt,
        baristaName: isWasteOrder
          ? wasteCashier?.name ?? wasteCashier?.username ?? cashierShift?.name ?? "—"
          : requestedCashier?.name ?? claims.name,
        baristaUserId: isWasteOrder ? wasteCashier?.id : requestedCashier?.id,
        items: orderItems,
        subtotal: isWasteOrder ? 0 : Number(rawOrder.subtotal) || 0,
        discount: isWasteOrder ? 0 : Number(rawOrder.discount) || 0,
        promoLabel: !isWasteOrder && typeof rawOrder.promoLabel === "string" ? rawOrder.promoLabel : undefined,
        promoItemIndex: typeof rawOrder.promoItemIndex === "number" && Number.isInteger(rawOrder.promoItemIndex)
          ? rawOrder.promoItemIndex
          : undefined,
        promoItemQty: typeof rawOrder.promoItemQty === "number" && Number.isInteger(rawOrder.promoItemQty)
          ? rawOrder.promoItemQty
          : undefined,
        total: isWasteOrder ? 0 : Number(rawOrder.total) || 0,
        paymentMethod: isWasteOrder ? "waste" : parsePayment(rawOrder.paymentMethod),
        serviceMode,
        ticketNo: isWasteOrder ? "" : typeof rawOrder.ticketNo === "string" ? rawOrder.ticketNo : "",
        paid: isWasteOrder ? 0 : Number(rawOrder.paid ?? rawOrder.total) || 0,
        change: isWasteOrder ? 0 : Number(rawOrder.change) || 0,
        recordType: isWasteOrder ? "Waste" : "Sale",
        voided: isWasteOrder ? false : Boolean(rawOrder.voided),
        voidReason: isWasteOrder ? undefined : (typeof rawOrder.voidReason === "string" ? rawOrder.voidReason : undefined),
        wasteReason,
      };

      // Calculate deductions using the exact Admin recipe/costing/addon configuration
      const deductionsByInventoryItem = new Map<
        string,
        {
          inventoryItemId: string;
          itemName: string;
          amount: number;
          unit: string;
          orderItemId?: string;
        }
      >();

      for (const line of order.items) {
        const ingredients = ingredientsForOrderLine(store, line);
        for (const ingredient of ingredients) {
          const matchedStock = store.inventory.find(
            (inv) =>
              (ingredient.inventoryItemId && inv.id === ingredient.inventoryItemId) ||
              inv.name.trim().toLowerCase() === ingredient.name.trim().toLowerCase(),
          );
          if (!matchedStock) continue;
          const usedAmount = roundQty(Number(ingredient.amount) * line.qty);
          if (usedAmount <= 0) continue;
          const existing = deductionsByInventoryItem.get(matchedStock.id);
          if (existing) {
            existing.amount = roundQty(existing.amount + usedAmount);
          } else {
            deductionsByInventoryItem.set(matchedStock.id, {
              inventoryItemId: matchedStock.id,
              itemName: matchedStock.name,
              amount: usedAmount,
              unit: ingredient.unit || matchedStock.unit || "pcs",
              orderItemId: line.productId,
            });
          }
        }
      }
      const deductions = [...deductionsByInventoryItem.values()];
      const excludedWasteInventoryItemIds = new Set(
        isWasteOrder && Array.isArray(rawOrder.excludedWasteInventoryItemIds)
          ? rawOrder.excludedWasteInventoryItemIds
              .filter((id: unknown): id is string => typeof id === "string")
              .map((id: string) => id.trim())
              .filter(Boolean)
          : [],
      );
      const selectedDeductions = deductions.filter(
        (deduction) => !excludedWasteInventoryItemIds.has(deduction.inventoryItemId),
      );

      const result = await createOrderAtomic({
        order,
        deductions: selectedDeductions,
      });

      if (!result.ok) {
        return NextResponse.json(
          { ok: false, error: result.error },
          { status: 400, headers: corsHeaders },
        );
      }

      if (isWasteOrder) {
        order.ticketNo = "";
      } else {
        order.ticketNo = result.ticketNo || order.ticketNo;
      }
      return NextResponse.json(
        { ok: true, ticketNo: order.ticketNo, order },
        { headers: corsHeaders },
      );
    }

    if (action === "void_checkout") {
      const rawOrder = body.order ?? {};
      const reason = String(body.reason ?? rawOrder.voidReason ?? "").trim();
      const items = orderItemsFromApi(rawOrder.items);
      if (items.length === 0 || !reason) {
        return NextResponse.json({ ok: false, error: "Checkout items and void reason are required." }, { status: 400, headers: corsHeaders });
      }

      let voidedBy = claims.userId;
      let voidedByName = claims.name;
      const store = await getFreshStore();
      if (claims.role !== "admin") {
        const managerUsername = String(body.managerUsername ?? "").trim().toLowerCase();
        const managerPassword = String(body.managerPassword ?? "");
        const manager = store.users.find((user) => user.username.trim().toLowerCase() === managerUsername);
        const managerRole = manager ? parseRole(String(manager.title ?? ""), manager.role) : "barista";
        const validPassword = manager && (manager.password.startsWith("$2")
          ? await bcrypt.compare(managerPassword, manager.password)
          : manager.password === managerPassword);
        if (!manager || !validPassword || managerRole !== "admin") {
          return NextResponse.json({ ok: false, error: "Manager or Admin credentials required to void." }, { status: 403, headers: corsHeaders });
        }
        // The cashier token identifies who rang up the order. The manager
        // whose credentials approved this void is the void actor.
        voidedBy = manager.id;
        voidedByName = manager.name;
      }

      const orderId = String(rawOrder.id || "").trim();
      const createdAt = orderTimestampFromApi(rawOrder.createdAt);
      if (!createdAt) {
        return NextResponse.json(
          { ok: false, error: "A valid device order timestamp is required." },
          { status: 400, headers: corsHeaders },
        );
      }
      const existingOrder = store.orders.find((entry) => entry.id === orderId);
      if (existingOrder) {
        if (existingOrder.voided) {
          return NextResponse.json(
            { ok: true, ticketNo: existingOrder.ticketNo, order: existingOrder },
            { headers: corsHeaders },
          );
        }
        return NextResponse.json(
          { ok: false, error: "Order id already belongs to a completed checkout." },
          { status: 409, headers: corsHeaders },
        );
      }

      const requestedCashierId = String(rawOrder.baristaUserId ?? '').trim();
      const requestedCashier = store.users.find((user) => {
        if (user.id !== requestedCashierId) return false;
        const role = parseRole(String(user.title ?? ''), user.role);
        return ['cashier', 'admin'].includes(role);
      });
      const order: Order = {
        id: orderId || `ord-${Date.now()}`,
        createdAt,
        baristaName: requestedCashier?.name ?? claims.name,
        baristaUserId: requestedCashier?.id,
        items,
        subtotal: Number(rawOrder.subtotal) || 0,
        discount: Number(rawOrder.discount) || 0,
        promoLabel: typeof rawOrder.promoLabel === "string" ? rawOrder.promoLabel : undefined,
        total: Number(rawOrder.total) || 0,
        paymentMethod: parsePayment(rawOrder.paymentMethod),
        ticketNo: "",
        paid: 0,
        change: 0,
        voided: true,
        voidedBy,
        voidedByName,
        voidReason: reason,
      };
      const result = await createOrderAtomic({ order, deductions: [], voidedBy });
      if (!result.ok) {
        return NextResponse.json({ ok: false, error: result.error }, { status: 400, headers: corsHeaders });
      }
      order.ticketNo = result.ticketNo;
      return NextResponse.json({ ok: true, ticketNo: order.ticketNo, order }, { headers: corsHeaders });
    }

    if (action === "void_order") {
      const orderId = String(body.orderId ?? "").trim();
      const reason = String(body.reason ?? "Voided from POS").trim();
      const managerUsername = typeof body.managerUsername === "string" ? body.managerUsername.trim().toLowerCase() : "";
      const managerPassword = typeof body.managerPassword === "string" ? body.managerPassword : "";

      let voidedBy = claims.userId;
      let voidedByName = claims.name;
      if (claims.role !== "admin") {
        if (!managerUsername || !managerPassword) {
          return NextResponse.json(
            { ok: false, error: "Manager approval required to void an order." },
            { status: 403, headers: corsHeaders },
          );
        }
        const store = await getFreshStore();
        const manager = store.users.find((u) => u.username.trim().toLowerCase() === managerUsername);
        const role = manager ? parseRole(String(manager.title ?? ""), manager.role) : "barista";
        if (!manager || role !== "admin") {
          return NextResponse.json(
            { ok: false, error: "Manager or Admin credentials required to void an order." },
            { status: 403, headers: corsHeaders },
          );
        }
        const valid = manager.password.startsWith("$2")
          ? await bcrypt.compare(managerPassword, manager.password)
          : manager.password === managerPassword;
        if (!valid) {
          return NextResponse.json(
            { ok: false, error: "Invalid manager password." },
            { status: 403, headers: corsHeaders },
          );
        }
        // Record the approving manager/admin, not the cashier's API token.
        voidedBy = manager.id;
        voidedByName = manager.name;
      }

      const res = await voidOrderAtomic(orderId, reason, voidedBy);
      return NextResponse.json(
        res.ok ? { ...res, voidedBy, voidedByName } : res,
        { status: res.ok ? 200 : 400, headers: corsHeaders },
      );
    }

    if (action === "delete_order") {
      return NextResponse.json(
        { ok: false, error: "Order deletion is only available to Admin." },
        { status: 403, headers: corsHeaders },
      );
    }

    if (action === "create_restock") {
      const record = body.restock ?? body;
      const id = String(record.id || `rst-${Date.now()}`);
      const inventoryItemId = record.inventoryItemId ? String(record.inventoryItemId) : null;
      const itemNameSnapshot = String(record.itemName ?? record.itemNameSnapshot ?? "");
      const quantityAdded = Number(record.quantityAdded) || 0;
      const createdAt = phIsoTimestamp(String(record.date ?? record.createdAt ?? "")) || new Date().toISOString();
      const purchaseQty = record.purchaseQty != null ? Number(record.purchaseQty) : null;
      const purchaseUnit = typeof record.purchaseUnit === "string" ? record.purchaseUnit : null;

      const store = await getFreshStore();
      if (!store.restocks.some((r) => r.id === id)) {
        await createRestockAtomic({
          id,
          inventoryItemId,
          itemNameSnapshot,
          quantityAdded,
          createdAt,
          purchaseQty,
          purchaseUnit,
        });
      }
      return NextResponse.json({ ok: true, id }, { headers: corsHeaders });
    }

    if (action === "edit_restock") {
      await editRestockAtomic({
        id: String(body.id),
        oldInventoryItemId: body.oldInventoryItemId ?? null,
        oldQuantity: Number(body.oldQuantity) || 0,
        newInventoryItemId: body.newInventoryItemId ?? null,
        newItemNameSnapshot: String(body.newItemNameSnapshot ?? ""),
        newQuantity: Number(body.newQuantity) || 0,
        newCreatedAt: phIsoTimestamp(String(body.newCreatedAt ?? "")) || new Date().toISOString(),
        newPurchaseQty: body.newPurchaseQty != null ? Number(body.newPurchaseQty) : null,
        newPurchaseUnit: body.newPurchaseUnit ?? null,
      });
      return NextResponse.json({ ok: true }, { headers: corsHeaders });
    }

    if (action === "delete_restock") {
      const id = String(body.id ?? "").trim();
      if (!id) {
        return NextResponse.json({ ok: false, error: "Missing restock id" }, { status: 400, headers: corsHeaders });
      }
      await deleteRestockAtomic({ id });
      return NextResponse.json({ ok: true }, { headers: corsHeaders });
    }

    if (action === "upsert_inventory_item") {
      const raw = body.item ?? {};
      const item: InventoryItem = {
        id: String(raw.id || `stock-${Date.now()}`),
        name: String(raw.name ?? "").trim(),
        unit: String(raw.unit || "pcs").trim(),
        cost: Number(raw.cost) || 0,
        stock: Number(raw.stock) || 0,
        maxStock: Number(raw.maxStock ?? raw.stock) || 0,
        openingStock: raw.openingStock != null ? Number(raw.openingStock) : undefined,
        purchaseUnitSize: raw.purchaseUnitSize != null ? Number(raw.purchaseUnitSize) : undefined,
        cupUsageAmount: raw.cupUsageAmount != null ? Number(raw.cupUsageAmount) : undefined,
        cupsMake: raw.cupsMake != null ? Number(raw.cupsMake) : undefined,
        inventoryType: typeof raw.inventoryType === "string" && raw.inventoryType.trim() ? raw.inventoryType.trim().slice(0, 60) : undefined,
      };
      if (!item.name) {
        return NextResponse.json({ ok: false, error: "Item name is required" }, { status: 400, headers: corsHeaders });
      }
      await updateStore((store) => {
        const idx = store.inventory.findIndex((i) => i.id === item.id);
        if (idx >= 0) {
          store.inventory[idx] = item;
        } else {
          store.inventory.push(item);
        }
      });
      return NextResponse.json({ ok: true, item }, { headers: corsHeaders });
    }

    if (action === "delete_inventory_item") {
      const id = String(body.id ?? "").trim();
      if (!id) {
        return NextResponse.json({ ok: false, error: "Missing inventory item id" }, { status: 400, headers: corsHeaders });
      }
      const res = await deleteInventoryItemRecord(id);
      if ("error" in res) {
        return NextResponse.json({ ok: false, error: res.error }, { status: 400, headers: corsHeaders });
      }
      return NextResponse.json({ ok: true }, { headers: corsHeaders });
    }

    if (action === "create_void_request") {
      const raw = body.request ?? body;
      const reqRecord: VoidRequest = {
        id: String(raw.id || `vr-${Date.now()}`),
        requestedAt: phIsoTimestamp(String(raw.requestedAt ?? "")) || new Date().toISOString(),
        requestedById: claims.userId,
        requestedByName: claims.name,
        reason: String(raw.reason || "Void requested"),
        status: "pending",
        orderId: typeof raw.orderId === "string" ? raw.orderId : undefined,
        items: Array.isArray(raw.items) ? raw.items : [],
        subtotal: Number(raw.subtotal) || 0,
        discount: Number(raw.discount) || 0,
        promoLabel: typeof raw.promoLabel === "string" ? raw.promoLabel : undefined,
        total: Number(raw.total) || 0,
        paymentMethod: parsePayment(raw.paymentMethod),
      };
      await insertVoidRequestRecord(reqRecord);
      return NextResponse.json({ ok: true, request: reqRecord }, { headers: corsHeaders });
    }

    if (action === "login_activity" || action === "barista_shift_activity") {
      const isStaffShift = action === "barista_shift_activity";
      const raw = body.activity ?? body;
      let staff: Awaited<ReturnType<typeof getFreshStore>>["users"][number] | undefined;
      let requestedUserId = claims.userId;
      if (isStaffShift) {
        requestedUserId = typeof raw.userId === "string" ? raw.userId : "";
        const isOwnStaffShift =
          (claims.role === "barista" || claims.role === "pos_cashier") &&
          requestedUserId === claims.userId;
        if (
          !["cashier", "admin"].includes(claims.role) &&
          !isOwnStaffShift
        ) {
          return NextResponse.json({ ok: false, error: "Owner access required to record a staff shift." }, { status: 403, headers: corsHeaders });
        }
        const store = await getFreshStore();
        staff = store.users.find((user) => user.id === requestedUserId);
        const staffRole = staff ? parseRole(String(staff.title ?? ""), staff.role) : null;
        if ((!staff && !isOwnStaffShift) || (staff && staffRole !== "barista" && staffRole !== "pos_cashier")) {
          return NextResponse.json({ ok: false, error: "Staff account not found." }, { status: 404, headers: corsHeaders });
        }
        if (!staff) {
          return NextResponse.json({ ok: false, error: "Staff account could not be verified." }, { status: 401, headers: corsHeaders });
        }

        const rawCredentials = body.credentials ?? raw.credentials;
        const credentials = rawCredentials && typeof rawCredentials === "object"
          ? rawCredentials as Record<string, unknown>
          : {};
        const credentialUsername = String(credentials.username ?? "").trim().toLowerCase();
        const credentialPassword = String(credentials.password ?? "");
        if (
          !credentialUsername ||
          credentialUsername !== staff.username.trim().toLowerCase() ||
          !credentialPassword
        ) {
          return NextResponse.json({ ok: false, error: "Enter this staff member’s valid username and password or PIN." }, { status: 401, headers: corsHeaders });
        }
        const passwordMatches = staff.password.startsWith("$2")
          ? await bcrypt.compare(credentialPassword, staff.password)
          : staff.password === credentialPassword || staff.password.trim() === credentialPassword.trim();
        if (!passwordMatches) {
          return NextResponse.json({ ok: false, error: "Staff password or PIN is incorrect." }, { status: 401, headers: corsHeaders });
        }

        const authMode = store.pos.attendanceAuthMode;
        const requiresPhoto = authMode === "photo_username_password" || authMode === "photo_full_name_pin";
        const rawPhoto = body.photoBase64 ?? raw.photoBase64;
        const photoBase64 = typeof rawPhoto === "string" ? rawPhoto : "";
        if (requiresPhoto && !photoBase64) {
          return NextResponse.json({ ok: false, error: "Capture a live attendance photo before recording this shift." }, { status: 400, headers: corsHeaders });
        }
        if (requiresPhoto && photoBase64.length > 2_800_000) {
          return NextResponse.json({ ok: false, error: "Attendance photo must be smaller than 2 MB." }, { status: 413, headers: corsHeaders });
        }

        const punchType: LoginActivity["type"] =
          raw.type === "logout"
            ? "logout"
            : raw.type === "break_start"
              ? "break_start"
              : raw.type === "break_end"
                ? "break_end"
                : "login";
        const openSession = pairLoginSessions(store.loginActivity).find(
          (session) => session.userId === staff!.id && !session.logoutAt,
        );
        const alreadyOnShift = Boolean(openSession);
        const onBreak = Boolean(openSession?.breakStartedAt);
        const transitionError =
          punchType === "login"
            ? alreadyOnShift
              ? "This staff member is already clocked in."
              : null
            : !alreadyOnShift
              ? "This staff member is not clocked in."
              : punchType === "break_start" && onBreak
                ? "This staff member is already on break."
                : punchType === "break_end" && !onBreak
                  ? "This staff member is not on break."
                  : null;
        if (transitionError) {
          return NextResponse.json({
            ok: false,
            error: transitionError,
          }, { status: 409, headers: corsHeaders });
        }

        let photoPath: string | undefined;
        if (requiresPhoto) {
          if (!/^[A-Za-z0-9+/]+={0,2}$/.test(photoBase64)) {
            return NextResponse.json({ ok: false, error: "Attendance photo data is invalid." }, { status: 400, headers: corsHeaders });
          }
          const photoBytes = Buffer.from(photoBase64, "base64");
          if (
            photoBytes.length === 0 ||
            photoBytes.length > 2 * 1024 * 1024 ||
            photoBytes[0] !== 0xff ||
            photoBytes[1] !== 0xd8 ||
            photoBytes[2] !== 0xff
          ) {
            return NextResponse.json({ ok: false, error: "Capture a valid JPEG attendance photo smaller than 2 MB." }, { status: 400, headers: corsHeaders });
          }
          const activityId = String(raw.id || `log-${Date.now()}`).replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 100);
          const safeTenantId = tenantId.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 100);
          const safeStaffId = staff.id.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 100);
          photoPath = `${safeTenantId}/${safeStaffId}/${activityId || crypto.randomUUID()}.jpg`;
          const { error: uploadError } = await supabaseAdmin()
            .storage
            .from("attendance-photos")
            .upload(photoPath, photoBytes, { contentType: "image/jpeg", upsert: false });
          if (uploadError) {
            throw new Error(`Unable to save attendance photo: ${uploadError.message}`);
          }
        }

        const entry = {
          id: String(raw.id || `log-${Date.now()}`),
          userId: staff.id,
          username: staff.username,
          name: staff.name,
          role: staff.role,
          type: punchType,
          at: phIsoTimestamp(String(raw.at ?? "")) || new Date().toISOString(),
          photoPath,
        };
        try {
          await insertLoginActivityRecord(entry);
        } catch (error) {
          if (photoPath) {
            const { error: cleanupError } = await supabaseAdmin()
              .storage
              .from("attendance-photos")
              .remove([photoPath]);
            if (cleanupError) {
              throw new Error(`Unable to record attendance (${error instanceof Error ? error.message : "unknown error"}); photo cleanup also failed: ${cleanupError.message}`);
            }
          }
          throw error;
        }
        return NextResponse.json({ ok: true, photoPath }, { headers: corsHeaders });
      }
      const queuedType: LoginActivity["type"] =
        raw.type === "logout"
          ? "logout"
          : raw.type === "break_start"
            ? "break_start"
            : raw.type === "break_end"
              ? "break_end"
              : "login";
      const entry = {
        id: String(raw.id || `log-${Date.now()}`),
        userId: staff?.id ?? requestedUserId,
        username: staff?.username ?? claims.username,
        name: staff?.name ?? claims.name,
        role: staff
          ? parseRole(String(staff.title ?? ""), staff.role)
          : claims.role,
        type: queuedType,
        at: phIsoTimestamp(String(raw.at ?? "")) || new Date().toISOString(),
      };
      await insertLoginActivityRecord(entry);
      if (!isStaffShift && queuedType === "login") {
        await updateStore((store) => {
          store.pos.isOpen = true;
          store.pos.openedBy = entry.name;
          store.pos.openedAt = entry.at;
        });
      }
      return NextResponse.json({ ok: true }, { headers: corsHeaders });
    }

    return NextResponse.json(
      { ok: false, error: `Unknown sync action: ${action}` },
      { status: 400, headers: corsHeaders },
    );
    });
  } catch (error) {
    return NextResponse.json(
      {
        ok: false,
        error: error instanceof Error ? error.message : "Sync operation failed",
      },
      { status: 500, headers: corsHeaders },
    );
  }
}
