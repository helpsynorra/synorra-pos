import { createClient } from "@supabase/supabase-js";
import { AsyncLocalStorage } from "node:async_hooks";
import { randomInt } from "node:crypto";
import { getSession } from "@/lib/auth";
import { nextTicketNo } from "@/lib/escpos";
import type {
  InventoryItem,
  AdminLedgerEntry,
  AdminLedgerKind,
  LoginActivity,
  MenuCategoryType,
  MenuItem,
  OffRequest,
  Order,
  OrderItem,
  PrintJob,
  PromotionCode,
  RecipeCosting,
  RecipeIngredient,
  Role,
  StaffUser,
  StoreData,
  UsageLog,
  VoidRequest,
} from "@/lib/types";
import { roundQty } from "@/lib/inventory";
import { hydrateOrderLine, inferMenuCategoryType, normalizeMenuAddons, normalizeMenuCategoryType, normalizeMenuStyles, normalizeMenuTypes, parseDrinkStyle, parseMenuImageOptions, parseStoredOrderAddons, stripMenuImage } from "@/lib/menu";
import { parsePayment } from "@/lib/payments";
import { DEFAULT_LOGIN_GATES, normalizeLoginGates } from "@/lib/staff-gates";
import { DEFAULT_STAFF_PERMISSIONS, DEFAULT_USERS, parseRole } from "@/lib/users";

const POS_STATE_ID = "synorra-pos";

let queue: Promise<unknown> = Promise.resolve();
let memoryStore: StoreData | null = null;
let memoryStoreReadAt = 0;
let memoryCommunePromotions: PromotionCode[] = [];
const tenantContext = new AsyncLocalStorage<string | null>();
const tenantStoreCache = new Map<string, { store: StoreData; readAt: number }>();
const GLOBAL_STORE_KEY = "__all_owners__";

async function activeOwnerId(): Promise<string | null> {
  const scopedOwnerId = tenantContext.getStore();
  if (scopedOwnerId !== undefined) return scopedOwnerId;
  const session = await getSession();
  if (session?.role === "cashier") return session.userId;
  if (session?.role === "barista" && isRealSupabaseConfigured()) {
    const { data } = await supabaseAdmin().from("staff_users").select("owner_id").eq("id", session.userId).maybeSingle();
    if (data?.owner_id) return data.owner_id;
  }
  if (session?.role === "admin" && isRealSupabaseConfigured()) {
    return (await legacyOwnerId()) ?? "cashier-1";
  }
  return null;
}

export function withStoreTenant<T>(ownerId: string | null, run: () => Promise<T>): Promise<T> {
  return tenantContext.run(ownerId, run);
}

export async function ownerIdForStaff(userId: string): Promise<string | null> {
  if (!isRealSupabaseConfigured()) return null;
  const { data } = await supabaseAdmin().from("staff_users").select("owner_id, role").eq("id", userId).maybeSingle();
  return data?.role === "cashier" ? userId : data?.owner_id ?? null;
}

export async function legacyOwnerId(): Promise<string | null> {
  if (!isRealSupabaseConfigured()) return null;
  const { data } = await supabaseAdmin().from("staff_users").select("id").eq("role", "cashier").order("created_at", { ascending: true, nullsFirst: true }).limit(1).maybeSingle();
  return data?.id ?? null;
}

export async function getOwnerAccounts(): Promise<StaffUser[]> {
  if (!isRealSupabaseConfigured()) return (await getStore()).users.filter((user) => user.role === "cashier");
  const supabase = supabaseAdmin();
  const [{ data, error }, { data: promotions, error: promotionsError }] = await Promise.all([
    supabase.from("staff_users").select("id,owner_id,username,email,password,password_changed,name,role,title,permissions").eq("role", "cashier").order("created_at"),
    supabase.from("promotions").select("owner_id,code,discount_type,discount_value,expires_at,redeemed_at,redeemed_order_id").order("created_at", { ascending: false }),
  ]);
  if (error) throw new Error(`Unable to read Owner accounts: ${error.message}`);
  if (promotionsError) throw new Error(`Unable to read promotion codes: ${promotionsError.message}`);
  return (data ?? []).map((row) => ({
    id: row.id, ownerId: row.owner_id ?? row.id, username: row.username, email: row.email ?? "",
    password: row.password ?? "", passwordChanged: Boolean(row.password_changed), name: row.name,
    role: "cashier", title: "Owner", permissions: {
      ...(row.permissions ?? {}),
      promoCodes: (promotions ?? []).filter((promo) => promo.owner_id === row.id).map((promo) => ({
        code: promo.code,
        discountType: promo.discount_type,
        discountValue: Number(promo.discount_value),
        expiresAt: promo.expires_at ?? undefined,
        redeemedAt: promo.redeemed_at ?? undefined,
        redeemedOrderId: promo.redeemed_order_id ?? undefined,
      })),
    },
  }));
}

/** Permanently remove an Owner and all records that belong to that store. */
export async function deleteOwnerAccountAndData(ownerId: string): Promise<void> {
  const db = supabaseAdmin();
  const { data: ownerStaff, error: staffReadError } = await db
    .from("staff_users")
    .select("id")
    .eq("owner_id", ownerId);
  if (staffReadError) {
    throw new Error(`Unable to read Owner staff accounts: ${staffReadError.message}`);
  }

  const staffIds = Array.from(
    new Set([ownerId, ...(ownerStaff ?? []).map((staff) => staff.id)]),
  );
  const { error: activityReferenceError } = await db
    .from("login_activity")
    .update({ user_id: null })
    .in("user_id", staffIds);
  if (activityReferenceError) {
    throw new Error(
      `Unable to preserve Owner login history: ${activityReferenceError.message}`,
    );
  }

  const { data: menuItems, error: menuReadError } = await db
    .from("menu_items")
    .select("id")
    .eq("owner_id", ownerId);
  if (menuReadError) {
    throw new Error(`Unable to read Owner menu items: ${menuReadError.message}`);
  }

  const menuItemIds = (menuItems ?? []).map((item) => item.id);
  if (menuItemIds.length > 0) {
    // Keep order-line snapshots but detach their optional live menu reference.
    // This also handles older deployments where the FK is still NO ACTION.
    const { error } = await db
      .from("order_items")
      .update({ menu_item_id: null })
      .in("menu_item_id", menuItemIds);
    if (error) {
      throw new Error(`Unable to preserve Owner order history: ${error.message}`);
    }
  }

  const ownerTables = [
    "recipe_costing_menu_items",
    "recipe_costing_ingredients",
    "recipe_costings",
    "usage_logs",
    "restocks",
    "void_requests",
    "off_requests",
    "login_activity",
    "promotions",
    "order_items",
    "orders",
    "recipes",
    "inventory_items",
    "menu_items",
    "menu_categories",
    "pos_state",
    "login_links",
    "ticket_counters",
    "admin_ledger_entries",
  ];

  for (const table of ownerTables) {
    const { error } = await db.from(table).delete().eq("owner_id", ownerId);
    if (error && !(table === "admin_ledger_entries" && error.code === "PGRST205")) {
      throw new Error(`Unable to delete Owner data from ${table}: ${error.message}`);
    }
  }

  // Release the globally unique email before deleting the Owner rows. This
  // also frees it if a legacy FK or orphaned relation prevents a staff row
  // from being removed by the delete below.
  const { error: emailReleaseError } = await db
    .from("staff_users")
    .update({ email: null })
    .in("id", staffIds);
  if (emailReleaseError) {
    throw new Error(`Unable to release the deleted Owner email: ${emailReleaseError.message}`);
  }

  const { error: staffError } = await db
    .from("staff_users")
    .delete()
    .eq("owner_id", ownerId);
  if (staffError) {
    throw new Error(`Unable to delete Owner staff accounts: ${staffError.message}`);
  }
  const { error: ownerError } = await db
    .from("staff_users")
    .delete()
    .eq("id", ownerId)
    .eq("role", "cashier");
  if (ownerError) {
    throw new Error(`Unable to delete the Owner account: ${ownerError.message}`);
  }

  invalidateStoreCache();
}

function cacheStore(ownerId: string | null, store: StoreData, readAt = Date.now()) {
  tenantStoreCache.set(ownerId ?? GLOBAL_STORE_KEY, { store, readAt });
  memoryStore = store;
  memoryStoreReadAt = readAt;
}

// memoryStore is a short-lived per-process read cache, not the source of
// truth - Supabase is. A row written by another instance (another serverless
// function, a second dev process, a direct DB edit) becomes visible to this
// process once the cached snapshot is older than this TTL. AdminShell
// re-renders every 5s, so 5s bounds cross-instance staleness to roughly one
// refresh cycle while still deduping the bursts of reads a single page
// render or action produces.
export const STORE_CACHE_TTL_MS = 5_000;

function invalidateStoreCache() {
  memoryStore = null;
  memoryStoreReadAt = 0;
  tenantStoreCache.clear();
}


function env(...names: string[]) {
  for (const name of names) {
    const value = process.env[name]?.trim().replace(/^['"]|['"]$/g, "");
    if (value) return value;
  }
  return undefined;
}

const DEFAULT_SUPABASE_URL = "https://mzulfloebacecqzponrk.supabase.co";

function resolveSupabaseUrl(): string {
  return (
    env(
      "SUPABASE_URL",
      "NEXT_PUBLIC_SUPABASE_URL",
      "commume_coffee_SUPABASE_URL",
      "NEXT_PUBLIC_commume_coffee_SUPABASE_URL",
    ) || DEFAULT_SUPABASE_URL
  );
}

function resolveSupabaseKey(): string {
  return (
    env(
      "SUPABASE_SERVICE_ROLE_KEY",
      "commume_coffee_SUPABASE_SERVICE_ROLE_KEY",
      "SUPABASE_SERVICE_ROLE_KEY_2",
      "SUPABASE_SECRET_KEY",
      "commume_coffee_SUPABASE_SECRET_KEY",
    ) || ""
  );
}

export function isRealSupabaseConfigured(): boolean {
  if (
    process.env.NODE_ENV === "development" &&
    env("SYNORRA_LOCAL_DEMO_MODE")?.toLowerCase() === "true"
  ) {
    return false;
  }
  const url = resolveSupabaseUrl();
  const key = resolveSupabaseKey();
  return Boolean(url && key && /^https:\/\/[^/]+\.supabase\.co$/.test(url));
}

export function supabaseAdmin() {
  const url = resolveSupabaseUrl();
  const key = resolveSupabaseKey();
  if (!key) {
    throw new Error("Server Supabase credentials are not configured.");
  }

  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

function formatDbStaffTitle(user: StaffUser): string {
  const rawTitle = (user.title ?? "").trim();
  if (user.role === "admin") {
    return "Admin";
  }
  if (user.role === "cashier") {
    return "Owner";
  }
  return rawTitle || "Barista";
}

const DEFAULT_INVENTORY: InventoryItem[] = [];

const DEFAULT_RECIPES: Record<string, RecipeIngredient[]> = {};

function emptyStore(): StoreData {
  const localAdminGate =
    process.env.NODE_ENV === "development" &&
    env("SYNORRA_LOCAL_DEMO_MODE")?.toLowerCase() === "true"
      ? env("SYNORRA_LOCAL_ADMIN_GATE")
      : undefined;
  return {
    pos: { isOpen: false, openedAt: null, openedBy: null, inventoryFeaturesEnabled: true, printButtonHidden: false },
    orders: [],
    printJobs: [],
    menu: [],
    categories: [],
    categoryTypes: {},
    users: DEFAULT_USERS.map((item) => ({ ...item })),
    inventory: DEFAULT_INVENTORY.map((item) => ({ ...item })),
    recipes: structuredClone(DEFAULT_RECIPES),
    recipeCostings: [],
    usageLogs: [],
    restocks: [],
    loginActivity: [],
    offRequests: [],
    voidRequests: [],
    loginGates: localAdminGate
      ? normalizeLoginGates({ admin: localAdminGate })
      : { ...DEFAULT_LOGIN_GATES },
  };
}


function uniqueCategories(values: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    const name = value.trim();
    if (!name) continue;
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(name);
  }
  return result;
}

function normalizeStore(store: StoreData): StoreData {
  store.pos = {
    ...(store.pos ?? {}),
    isOpen: store.pos?.isOpen ?? false,
    openedAt: store.pos?.openedAt ?? null,
    openedBy: store.pos?.openedBy ?? null,
    inventoryFeaturesEnabled: store.pos?.inventoryFeaturesEnabled ?? true,
    printButtonHidden: store.pos?.printButtonHidden === true,
  };
  const categoryByProduct = new Map(
    (Array.isArray(store.menu) ? store.menu : []).map((item) => [
      item.id,
      item.category,
    ]),
  );
  if (!Array.isArray(store.orders)) {
    store.orders = [];
  } else {
    store.orders = store.orders
      .filter(
        (order): order is Order =>
          Boolean(order && typeof order === "object" && typeof order.id === "string" && !order.deletedAt),
      )
      .map((order: Order) => ({
        ...order,
        items: Array.isArray(order.items)
          ? order.items.filter((item) => item && typeof item === "object")
          : [],
        paymentMethod: parsePayment(order.paymentMethod),
        voided: Boolean(order.voided),
        voidedBy: typeof order.voidedBy === "string" ? order.voidedBy : undefined,
        voidedByName: typeof order.voidedByName === "string" ? order.voidedByName : undefined,
        voidReason: typeof order.voidReason === "string" ? order.voidReason : "",
      }))
      .map((order: Order) => ({
        ...order,
        items: order.items.map((item) => ({
          ...item,
          category: item.category ?? categoryByProduct.get(item.productId),
        })),
      }));
  }
  if (!Array.isArray(store.printJobs)) {
    store.printJobs = [];
  } else {
    store.printJobs = store.printJobs.filter(
      (job) =>
        job &&
        typeof job.id === "string" &&
        typeof job.orderId === "string" &&
        (job.type === "cup-label" || job.type === "customer-receipt"),
    );
  }
  // An empty menu/categories set is valid, intentional state once the
  // database has been initialized - normalizeStore must never fabricate
  // defaults into it (that is how deleted items used to reappear, KAN-123).
  // A new store starts with an empty menu and categories.
  if (!Array.isArray(store.menu)) {
    store.menu = [];
  } else {
    store.menu = store.menu
      .filter(
        (item): item is MenuItem =>
          Boolean(item && typeof item === "object" && typeof item.id === "string"),
      )
      .map((item: MenuItem) => ({
        ...item,
        available: item.available !== false,
        image: item.image || "/images/drinks.jpg",
        types: normalizeMenuTypes(item),
        styles: normalizeMenuStyles(item),
        addons: normalizeMenuAddons(item),
      }));
  }
  store.categories = uniqueCategories([
    ...(Array.isArray(store.categories) ? store.categories : []),
    ...store.menu.map((item) => item.category),
  ]);
  const categoryTypeEntries = Object.fromEntries(
    store.categories.map((name) => {
      const key = name.trim();
      const type = normalizeMenuCategoryType(
        store.categoryTypes?.[key] ??
        store.categoryTypes?.[key.toLowerCase()] ??
        inferMenuCategoryType(key),
      );
      return [key, type];
    }),
  ) as Record<string, MenuCategoryType>;
  store.categoryTypes = categoryTypeEntries;
  if (!Array.isArray(store.inventory)) {
    store.inventory = [];
  } else {
    store.inventory = store.inventory.map((item) => ({
      ...item,
      stock: Number(item.stock) || 0,
      maxStock: Number(item.maxStock) || 0,
      cost: Number(item.cost) || 0,
      unit: item.unit || "pcs",
    }));

  }
  if (!Array.isArray(store.recipeCostings)) {
    store.recipeCostings = [];
  } else {
    store.recipeCostings = store.recipeCostings
      .filter((costing) => costing && typeof costing.name === "string" && Array.isArray(costing.menuItems) && Array.isArray(costing.ingredients))
      .map((costing, index) => ({
        ...costing,
        id: typeof costing.id === "string" && costing.id ? costing.id : `recipe-costing-${index}`,
      }));
  }
  if (!store.recipes || typeof store.recipes !== "object") {
    store.recipes = structuredClone(DEFAULT_RECIPES);
  } else {
    const menuIds = new Set(store.menu.map((item) => item.id));
    const isLegacyDefaultRecipe = (ingredients: RecipeIngredient[]) => {
      const legacyIds = new Set(["coffee-beans", "milk", "sugar", "cups-peta", "cups-daba", "cups-hot", "matcha-powder"]);
      return ingredients.length > 0 && ingredients.every((ingredient) => legacyIds.has(ingredient.inventoryItemId));
    };
    store.recipes = Object.fromEntries(
      Object.entries(store.recipes)
        .filter(([recipeKey, ingredients]) => !menuIds.has(recipeKey) && !(Array.isArray(ingredients) && isLegacyDefaultRecipe(ingredients)))
        .map(([recipeName, ingredients]) => [
          recipeName,
          Array.isArray(ingredients)
            ? ingredients.map((ingredient) =>
                ingredient.inventoryItemId === "milk" && Number(ingredient.amount) >= 100
                  ? { ...ingredient, amount: 13.33, unit: "ml" }
                  : ingredient,
              )
            : [],
        ]),
    );
  }
  if (!Array.isArray(store.usageLogs)) {
    store.usageLogs = [];
  } else {
    const activeOrderIds = new Set(store.orders.map((order) => order.id));
    const configuredRecipeKeys = new Set(Object.keys(store.recipes));
    const menuNameById = new Map(store.menu.map((item) => [item.id, item.name]));
    store.usageLogs = store.usageLogs
      .filter((usage) => {
        if (usage.orderId && !activeOrderIds.has(usage.orderId)) return false;
        if (!usage.orderId || !usage.orderItemId) return true;
        const recipeName = menuNameById.get(usage.orderItemId);
        return configuredRecipeKeys.has(usage.orderItemId) || (recipeName ? configuredRecipeKeys.has(recipeName) : false);
      })
      .map((usage) =>
        /milk/i.test(usage.itemName) && Number(usage.usedAmount) >= 100
          ? { ...usage, usedAmount: Number((Number(usage.usedAmount) / 10).toFixed(2)), unit: "ml" }
          : usage,
      );
  }
  if (!Array.isArray(store.restocks)) {
    store.restocks = [];
  }
  if (!Array.isArray(store.loginActivity)) {
    store.loginActivity = [];
  } else {
    store.loginActivity = store.loginActivity.filter(
      (entry) =>
        entry &&
        typeof entry.id === "string" &&
        typeof entry.userId === "string" &&
        typeof entry.at === "string" &&
        (entry.type === "login" || entry.type === "logout"),
    );
  }
  if (!Array.isArray(store.offRequests)) {
    store.offRequests = [];
  }
  if (!Array.isArray(store.voidRequests)) {
    store.voidRequests = [];
  } else {
    store.voidRequests = store.voidRequests.filter(
      (request) =>
        request &&
        typeof request.id === "string" &&
        (request.status === "pending" ||
          request.status === "approved" ||
          request.status === "denied") &&
        Array.isArray(request.items),
    );
  }
  store.loginGates = normalizeLoginGates(store.loginGates);


  if (!Array.isArray(store.users) || store.users.length === 0) {
    store.users = DEFAULT_USERS.map((item) => ({ ...item }));
  } else {
    const normalizedUsers = store.users.map((item: StaffUser) => {
      const resolvedRole = parseRole(String(item.title ?? ""), item.role);
      return {
        ...item,
        username: String(item.username ?? "").trim().toLowerCase(),
        name: item.name || item.username,
        title:
          item.title ||
          (resolvedRole === "admin"
            ? "Admin"
            : resolvedRole === "cashier"
                ? "Owner"
                : "Barista"),
        role: resolvedRole,
        password: String(item.password ?? ""),
      };
    });

    store.users = Array.from(
      new Map(normalizedUsers.map((user) => [user.id, user])).values(),
    );
    if (!store.users.some((user) => user.role === "barista" && user.password)) {
      const baristaUsernameTaken = store.users.some((user) => user.username === "barista");
      store.users.push({
        id: "barista-1",
        username: baristaUsernameTaken ? `barista-${Date.now().toString(36)}` : "barista",
        password: "synorra",
        name: "Barista",
        role: "barista",
        title: "Barista",
      });
    }
  }
  return store;
}

const MENU_PHOTO_BUCKET = "menu-photos";

export async function uploadPublicMenuPhoto(
  filename: string,
  bytes: Buffer,
  contentType: string,
) {
  const supabase = supabaseAdmin();
  if (supabase) {
    try {
      const { data: buckets, error: listError } = await supabase.storage.listBuckets();
      if (!listError) {
        if (!buckets?.some((bucket) => bucket.name === MENU_PHOTO_BUCKET)) {
          await supabase.storage.createBucket(MENU_PHOTO_BUCKET, { public: true });
        }
        const { error } = await supabase.storage
          .from(MENU_PHOTO_BUCKET)
          .upload(filename, bytes, { contentType, upsert: true });
        if (!error) {
          const { data } = supabase.storage.from(MENU_PHOTO_BUCKET).getPublicUrl(filename);
          return data.publicUrl;
        }
      }
    } catch {
      // Fall through to data URL
    }
  }
  return `data:${contentType};base64,${bytes.toString("base64")}`;
}

async function readStore(options?: { fresh?: boolean; ownerId?: string | null }): Promise<StoreData> {
  const ownerId = options && Object.prototype.hasOwnProperty.call(options, "ownerId")
    ? options.ownerId ?? null
    : await activeOwnerId();
  const cacheKey = ownerId ?? GLOBAL_STORE_KEY;
  const cached = tenantStoreCache.get(cacheKey);
  if (!options?.fresh && cached && Date.now() - cached.readAt < STORE_CACHE_TTL_MS) {
    memoryStore = cached.store;
    memoryStoreReadAt = cached.readAt;
    return cached.store;
  }
  const previousStore = cached?.store ?? null;
  if (!isRealSupabaseConfigured()) {
    if (!cached) {
      cacheStore(ownerId, normalizeStore(emptyStore()));
    } else {
      memoryStore = cached.store;
    }
    return memoryStore!;
  }
  const supabase = supabaseAdmin();

  try {
    const tenantQuery = <T,>(query: T): T =>
      ownerId ? (query as any).eq("owner_id", ownerId) as T : query;
    const [pos, users, categories, menu, inventory, orders, orderItems, usageLogs, restocks, recipes, recipeCostings, recipeCostingMenuItems, recipeCostingIngredients, loginActivity, offRequests, voidRequests, promotions, loginGates] = await Promise.all([
      ownerId
        ? supabase.from("pos_state").select("*").eq("owner_id", ownerId).maybeSingle()
        : supabase.from("pos_state").select("*").eq("id", POS_STATE_ID).maybeSingle(),
      tenantQuery(supabase.from("staff_users").select("*")).order("created_at"),
      tenantQuery(supabase.from("menu_categories").select("*")).order("name"),
      tenantQuery(supabase.from("menu_items").select("*")).order("created_at"),
      tenantQuery(supabase.from("inventory_items").select("*")).order("created_at"),
      tenantQuery(supabase.from("orders").select("*")).is("deleted_at", null).order("created_at", { ascending: false }),
      tenantQuery(supabase.from("order_items").select("*")).order("created_at"),
      tenantQuery(supabase.from("usage_logs").select("*")).order("created_at"),
      tenantQuery(supabase.from("restocks").select("*")).order("created_at"),
      tenantQuery(supabase.from("recipes").select("*")).order("created_at"),
      tenantQuery(supabase.from("recipe_costings").select("*")).order("created_at"),
      tenantQuery(supabase.from("recipe_costing_menu_items").select("*")).order("created_at"),
      tenantQuery(supabase.from("recipe_costing_ingredients").select("*")).order("created_at"),
      tenantQuery(supabase.from("login_activity").select("*")).order("at"),
      tenantQuery(supabase.from("off_requests").select("*")).order("created_at"),
      tenantQuery(supabase.from("void_requests").select("*")).order("requested_at", { ascending: false }),
      tenantQuery(supabase.from("promotions").select("*")).order("created_at", { ascending: false }),
      ownerId
        ? supabase.from("login_links").select("*").eq("owner_id", ownerId).maybeSingle()
        : supabase.from("login_links").select("*").eq("id", POS_STATE_ID).maybeSingle(),
    ]);
    const failedRead = (
      [
        ["pos_state", pos.error],
        ["staff_users", users.error],
        ["menu_categories", categories.error],
        ["menu_items", menu.error],
        ["inventory_items", inventory.error],
        ["orders", orders.error],
        ["order_items", orderItems.error],
        ["usage_logs", usageLogs.error],
        ["restocks", restocks.error],
        ["recipes", recipes.error],
        ["recipe_costings", recipeCostings.error],
        ["recipe_costing_menu_items", recipeCostingMenuItems.error],
        ["recipe_costing_ingredients", recipeCostingIngredients.error],
        ["login_activity", loginActivity.error],
        ["off_requests", offRequests.error],
        ["void_requests", voidRequests.error],
        ["promotions", promotions.error],
        ["login_links", loginGates.error],
      ] as const
    ).find(([, error]) => error);
    if (failedRead?.[1]) {
      const [table, error] = failedRead;
      throw new Error(`Unable to read ${table} from Supabase: ${error.message}`);
    }

    const virgin =
      (menu.data ?? []).length === 0 &&
      (categories.data ?? []).length === 0 &&
      (users.data ?? []).length === 0 &&
      (orders.data ?? []).length === 0 &&
      (inventory.data ?? []).length === 0;
    if (virgin && !ownerId) {
      await seedInitialStore(supabase);
      return readStore({ ...options, fresh: true, ownerId });
    }

    const base = emptyStore();
    const rows = (orders.data ?? []).filter((row) => !row.deleted_at);
    const activeOrderIds = new Set(rows.map((row) => row.id));
    const items = orderItems.data ?? [];
    const store = normalizeStore({
      ...base,
      pos: pos.data ? { isOpen: Boolean(pos.data.is_open), openedAt: pos.data.opened_at, openedBy: pos.data.opened_by_name ?? pos.data.opened_by, inventoryFeaturesEnabled: pos.data.inventory_features_enabled !== false, printButtonHidden: pos.data.print_button_hidden === true } : base.pos,
      users: Array.from(
        new Map(
          (users.data ?? []).map((row) => [
            row.id,
            {
              id: row.id,
              ownerId: row.owner_id ?? undefined,
              username: row.username,
              email: row.email ?? "",
              password: row.password,
              passwordChanged: Boolean(row.password_changed),
              permissions: {
                ...(row.permissions ?? {}),
                promoCodes: (promotions.data ?? [])
                  .filter((promo) => promo.owner_id === row.id)
                  .map((promo) => ({
                    code: promo.code,
                    discountType: promo.discount_type,
                    discountValue: Number(promo.discount_value),
                    expiresAt: promo.expires_at ?? undefined,
                    redeemedAt: promo.redeemed_at ?? undefined,
                    redeemedOrderId: promo.redeemed_order_id ?? undefined,
                  })),
              },
              name: row.name,
              role: parseRole(String(row.role ?? row.title ?? ""), String(row.title ?? row.username ?? "")),
              title: row.role === "admin" ? "Admin" : row.role === "cashier" ? "Owner" : row.title || "Barista",
            },
          ]),
        ).values(),
      ),
      categories: (categories.data ?? []).map((row) => row.name),
      categoryTypes: Object.fromEntries(
        (categories.data ?? []).map((row) => [
          String(row.name ?? "").trim(),
          normalizeMenuCategoryType(row.type ?? inferMenuCategoryType(String(row.name ?? ""))),
        ]),
      ) as Record<string, MenuCategoryType>,
      menu: (menu.data ?? []).map((row) => {
        const categoryRow = (categories.data ?? []).find((entry) => entry.id === row.category_id);
        const category = categoryRow?.name ?? "Other";
        const categoryType = normalizeMenuCategoryType(
          categoryRow?.type ?? inferMenuCategoryType(category),
        );
        const legacy = parseMenuImageOptions(row.image);
        const hasStoredStyles = Array.isArray(row.styles);
        const storedStyles = hasStoredStyles
          ? row.styles.flatMap((style: unknown) => (style === "hot" || style === "iced" ? [style] : []))
          : [];
        const storedAddons = Array.isArray(row.addons) ? row.addons : [];
        return {
          id: row.id,
          name: row.name,
          price: row.price,
          category,
          categoryType,
          image: stripMenuImage(row.image),
          available: row.available,
          types: normalizeMenuTypes({ types: row.types }),
          styles: normalizeMenuStyles({ category, categoryType, styles: hasStoredStyles ? storedStyles : legacy.styles }),
          addons: normalizeMenuAddons({ addons: storedAddons.length > 0 ? storedAddons : legacy.addons }),
        };
      }),
      inventory: (inventory.data ?? []).map((row) => ({
        id: row.id,
        ownerId: row.owner_id ?? undefined,
        name: row.name,
        unit: row.unit,
        cost: Number(row.cost),
        stock: Number(row.stock),
        maxStock: Number(row.max_stock),
        openingStock: row.opening_stock != null ? Number(row.opening_stock) : undefined,
        purchaseUnitSize: row.purchase_unit_size != null ? Number(row.purchase_unit_size) : undefined,
        cupUsageAmount: row.cup_usage_amount != null ? Number(row.cup_usage_amount) : undefined,
        cupsMake: row.cups_make != null ? Number(row.cups_make) : undefined,
      })),
      orders: rows.map((row) => ({
        id: row.id,
        ownerId: row.owner_id ?? undefined,
        createdAt: row.created_at,
        baristaName: row.barista_name,
        baristaUserId: row.barista_user_id ?? undefined,
        items: items.filter((item) => item.order_id === row.id).map((item) => hydrateOrderLine({
          productId: item.product_id_snapshot,
          name: item.name_snapshot,
          qty: item.qty,
          price: item.price_snapshot,
          style: parseDrinkStyle(item.style),
          addons: parseStoredOrderAddons(item.addons),
          serviceMode: item.service_mode === "take-out" ? "take-out" : item.service_mode === "dine-in" ? "dine-in" : undefined,
        })),
        subtotal: row.subtotal,
        discount: row.discount,
        promoLabel: row.promo_label ?? undefined,
        total: row.total,
        paymentMethod: parsePayment(row.payment_method),
        serviceMode: row.service_mode === "dine-in" || row.service_mode === "take-out"
          ? row.service_mode
          : items.find((item) => item.order_id === row.id && (item.service_mode === "dine-in" || item.service_mode === "take-out"))?.service_mode,
        ticketNo: row.ticket_no,
        recordType: row.record_type === "Purchase" ? "Purchase" : "Sale",
        paid: row.paid,
        change: row.change,
        voided: row.voided,
        voidedBy: row.voided_by ?? undefined,
        voidedByName: row.voided_by_name ?? undefined,
        voidReason: row.void_reason ?? undefined,
      })),
      usageLogs: (usageLogs.data ?? []).filter((row) => !row.order_id || activeOrderIds.has(row.order_id)).map((row) => ({ id: row.id, ownerId: row.owner_id ?? undefined, orderId: row.order_id ?? "", orderItemId: row.order_item_id ?? "", inventoryItemId: row.inventory_item_id ?? undefined, date: row.created_at, itemName: row.item_name_snapshot, usedAmount: Number(row.used_amount), unit: row.unit })),
      restocks: (restocks.data ?? []).map((row) => ({ id: row.id, ownerId: row.owner_id ?? undefined, inventoryItemId: row.inventory_item_id ?? undefined, itemName: row.item_name_snapshot, quantityAdded: Number(row.quantity_added), purchaseQty: row.purchase_qty == null ? undefined : Number(row.purchase_qty), purchaseUnit: row.purchase_unit ?? undefined, date: row.created_at })),
      recipes: Object.fromEntries((recipes.data ?? []).reduce((entries, row) => { const list = entries.get(row.menu_item_id) ?? []; list.push({ inventoryItemId: row.inventory_item_id, name: "", amount: Number(row.amount), unit: row.unit }); entries.set(row.menu_item_id, list); return entries; }, new Map<string, RecipeIngredient[]>())) ,
      recipeCostings: (recipeCostings.data ?? []).map((row) => ({
        id: row.id,
        ownerId: row.owner_id ?? undefined,
        name: row.name,
        menuItems: (recipeCostingMenuItems.data ?? [])
          .filter((item) => item.recipe_costing_id === row.id)
          .map((item) => item.menu_item_name),
        ingredients: (recipeCostingIngredients.data ?? [])
          .filter((ingredient) => ingredient.recipe_costing_id === row.id)
          .map((ingredient) => ({
            inventoryItemId: ingredient.inventory_item_id ?? (ingredient.name ? "other" : ""),
            name: ingredient.name,
            amount: Number(ingredient.amount),
            unit: ingredient.unit,
          })),
        hotCupInventoryItemId: row.hot_cup_inventory_item_id ?? undefined,
        icedCupInventoryItemId: row.iced_cup_inventory_item_id ?? undefined,
        otherCupInventoryItemId: row.other_cup_inventory_item_id ?? undefined,
      })),
      loginActivity: (loginActivity.data ?? []).map((row) => ({
        id: row.id,
        ownerId: row.owner_id ?? undefined,
        userId: row.user_id ?? row.id,
        username: row.username,
        name: row.name,
        role: row.role,
        type: row.type,
        at: row.at,
      })),
      offRequests: (offRequests.data ?? []).map((row) => ({
        id: row.id,
        ownerId: row.owner_id ?? undefined,
        userId: row.user_id ?? row.id,
        name: row.name,
        date: row.date,
        reason: row.reason,
        status: row.status,
        createdAt: row.created_at,
      })),
      voidRequests: (voidRequests.data ?? []).map(voidRequestFromRow),
      loginGates: loginGates.data
        ? { admin: loginGates.data.admin_path }
        : base.loginGates,
    });
    if (previousStore) {
      store.printJobs = previousStore.printJobs;
    }
    cacheStore(ownerId, store);
    return store;
  } catch (error) {
    throw new Error(
      `Unable to read store: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}

async function writeStore(store: StoreData): Promise<void> {
  const ownerId = await activeOwnerId();
  const posStateId = ownerId ?? POS_STATE_ID;
  if (Array.isArray(store.printJobs) && store.printJobs.length > 300) store.printJobs = store.printJobs.slice(-300);
  cacheStore(ownerId, store);
  if (!isRealSupabaseConfigured()) return;
  const supabase = supabaseAdmin();
  // Orders, staff accounts, and usage logs have dedicated transactional
  // write paths. A generic snapshot save must not replay stale foreign keys
  // or resurrect rows that were intentionally deleted.
  const inventoryRows = store.inventory.map((item) => ({
    id: item.id,
    owner_id: ownerId ?? item.ownerId ?? POS_STATE_ID,
    name: item.name,
    unit: item.unit,
    cost: item.cost,
    stock: item.stock,
    max_stock: item.maxStock,
    opening_stock: item.openingStock ?? null,
    purchase_unit_size: item.purchaseUnitSize ?? null,
    cup_usage_amount: item.cupUsageAmount ?? null,
    cups_make: item.cupsMake ?? null,
  }));
  const restockRows = store.restocks.map((record) => ({
    id: record.id,
    owner_id: ownerId ?? record.ownerId ?? POS_STATE_ID,
    item_name_snapshot: record.itemName,
    quantity_added: record.quantityAdded,
    inventory_item_id: record.inventoryItemId ?? null,
    purchase_qty: record.purchaseQty ?? null,
    purchase_unit: record.purchaseUnit ?? null,
  }));

  const operations = await Promise.all([
    supabase.from("pos_state").upsert({ id: posStateId, owner_id: ownerId ?? POS_STATE_ID, is_open: store.pos.isOpen, opened_at: store.pos.openedAt, opened_by_name: store.pos.openedBy, inventory_features_enabled: store.pos.inventoryFeaturesEnabled, print_button_hidden: store.pos.printButtonHidden, updated_at: new Date().toISOString() }),
    supabase.from("login_links").upsert({
      id: posStateId,
      owner_id: ownerId ?? POS_STATE_ID,
      admin_path: store.loginGates.admin,
      updated_at: new Date().toISOString(),
    }, { onConflict: "id" }),
    ...(inventoryRows.length > 0
      ? [supabase.from("inventory_items").upsert(inventoryRows, { onConflict: "id" })]
      : []),
    ...(restockRows.length > 0
      ? [supabase.from("restocks").upsert(restockRows, { onConflict: "id" })]
      : []),
  ]);
  const error = operations.find((result) => result.error)?.error;
  if (error) throw new Error(`Unable to save store data: ${error.message}`);
  cacheStore(ownerId, store);
}

// Bootstrap defaults directly - no StoreData snapshot is involved, so
// nothing stale can leak in. Each write ignores rows another simultaneous
// request may already have seeded, making the virgin-database check safe
// across concurrent server requests.
async function seedInitialStore(
  supabase: ReturnType<typeof supabaseAdmin>,
): Promise<void> {
  const ownerId = await legacyOwnerId() ?? "cashier-1";
  const results = await Promise.all([
    supabase.from("staff_users").upsert(
      DEFAULT_USERS.map((user) => ({
        id: user.id,
        owner_id: user.role === "admin" ? null : ownerId,
        username: user.username.trim().toLowerCase(),
        password: user.password,
        name: user.name,
        role: user.role === "admin" ? "admin" : "barista",
        title: user.title,
      })),
      { onConflict: "id", ignoreDuplicates: true },
    ),
    supabase.from("pos_state").upsert({
      id: ownerId,
      owner_id: ownerId,
      is_open: false,
      opened_at: null,
      opened_by_name: null,
      updated_at: new Date().toISOString(),
    }),
  ]);
  const seedError = results.find((result) => result.error)?.error;
  if (seedError) {
    throw new Error(`Unable to seed store data: ${seedError.message}`);
  }
}

/** Create a new Owner's blank operational store. */
export async function initializeOwnerStore(ownerId: string): Promise<void> {
  const supabase = supabaseAdmin();
  const [pos, links] = await Promise.all([
    supabase.from("pos_state").upsert({ id: ownerId, owner_id: ownerId, is_open: false, opened_at: null, opened_by_name: null, inventory_features_enabled: true, print_button_hidden: false, updated_at: new Date().toISOString() }, { onConflict: "id" }),
    supabase.from("login_links").upsert({ id: ownerId, owner_id: ownerId, admin_path: "back-office", updated_at: new Date().toISOString() }, { onConflict: "id" }),
  ]);
  for (const result of [pos, links]) {
    if (result.error) throw new Error(`Unable to initialize Owner store: ${result.error.message}`);
  }
}

function withStore<T>(
  fn: (store: StoreData) => Promise<T> | T,
  options?: { fresh?: boolean; ownerId?: string | null },
): Promise<T> {
  const run = queue.then(async () => {
    const store = await readStore(options);
    return fn(store);
  });
  queue = run.then(
    () => undefined,
    () => undefined,
  );
  return run;
}

export function getStore(options?: { ownerId?: string | null }): Promise<StoreData> {
  return withStore((store) => store, options);
}

// Validation that must not run against a stale snapshot (e.g. checking
// whether an order is already voided before inserting a related row).
export function getFreshStore(options?: { ownerId?: string | null }): Promise<StoreData> {
  return withStore((store) => store, { ...options, fresh: true });
}

function adminLedgerEntryFromRow(row: {
  id: string;
  kind: AdminLedgerKind;
  title: string;
  reason: string | null;
  amount: number | string;
  entry_date: string;
}): AdminLedgerEntry {
  return {
    id: row.id,
    kind: row.kind,
    title: row.title,
    reason: row.reason ?? "",
    amount: Number(row.amount),
    date: row.entry_date,
  };
}

export async function getAdminLedgerEntries(): Promise<{
  expenses: AdminLedgerEntry[];
  credits: AdminLedgerEntry[];
  error?: string;
}> {
  if (!isRealSupabaseConfigured()) {
    return { expenses: [], credits: [] };
  }
  const supabase = supabaseAdmin();
  const ownerId = await activeOwnerId() ?? POS_STATE_ID;
  const entries: AdminLedgerEntry[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await supabase
      .from("admin_ledger_entries")
      .select("id, kind, title, reason, amount, entry_date")
      .eq("owner_id", ownerId)
      .order("entry_date", { ascending: false })
      .order("created_at", { ascending: false })
      .range(offset, offset + 999);
    if (error) {
      if (error.code === "PGRST205" || error.code === "42P01") {
        return {
          expenses: [],
          credits: [],
          error: "Sales ledger is not installed in Supabase yet. Apply migration 20261006000700_sales_summary_and_ledger.sql.",
        };
      }
      throw new Error(`Unable to read admin ledger entries from Supabase: ${error.message}`);
    }
    const rows = data ?? [];
    entries.push(...rows.map((row) => adminLedgerEntryFromRow(row)));
    if (rows.length < 1000) break;
  }

  return {
    expenses: entries.filter((entry) => entry.kind === "expense"),
    credits: entries.filter((entry) => entry.kind === "credit"),
  };
}

export async function insertAdminLedgerEntryRecord(
  entry: Omit<AdminLedgerEntry, "date">,
): Promise<AdminLedgerEntry> {
  const supabase = supabaseAdmin();
  const ownerId = await activeOwnerId() ?? POS_STATE_ID;
  const { data, error } = await supabase
    .from("admin_ledger_entries")
    .insert({
      id: entry.id,
      owner_id: ownerId,
      kind: entry.kind,
      title: entry.title,
      reason: entry.reason,
      amount: entry.amount,
    })
    .select("id, kind, title, reason, amount, entry_date")
    .single();
  if (error) {
    throw new Error(`Unable to save ${entry.kind} entry to Supabase: ${error.message}`);
  }
  return adminLedgerEntryFromRow(data);
}

export async function importAdminLedgerEntries(
  entries: AdminLedgerEntry[],
): Promise<void> {
  if (entries.length > 5000) {
    throw new Error("Too many legacy ledger entries to import at once.");
  }
  const supabase = supabaseAdmin();
  const ownerId = await activeOwnerId() ?? POS_STATE_ID;
  if (entries.length > 0) {
    const { error } = await supabase.from("admin_ledger_entries").upsert(
      entries.map((entry) => ({
        id: entry.id,
        owner_id: ownerId,
        kind: entry.kind,
        title: entry.title,
        reason: entry.reason,
        amount: entry.amount,
        entry_date: entry.date,
      })),
      { onConflict: "id", ignoreDuplicates: true },
    );
    if (error) {
      throw new Error(`Unable to import existing ledger entries to Supabase: ${error.message}`);
    }
  }
}

export async function deleteAdminLedgerEntryRecord(
  id: string,
  kind: AdminLedgerKind,
): Promise<void> {
  const supabase = supabaseAdmin();
  const { data, error } = await supabase
    .from("admin_ledger_entries")
    .delete()
    .eq("id", id)
    .eq("kind", kind)
    .eq("owner_id", await activeOwnerId() ?? POS_STATE_ID)
    .select("id")
    .maybeSingle();
  if (error) {
    throw new Error(`Unable to delete ${kind} entry from Supabase: ${error.message}`);
  }
  if (!data) {
    throw new Error("Ledger entry was not found.");
  }
}

export async function saveUsageLogRecords(records: UsageLog[]): Promise<void> {
  await enqueue(async () => {
    if (isRealSupabaseConfigured() && records.length > 0) {
      const supabase = supabaseAdmin();
      const ownerId = await activeOwnerId() ?? POS_STATE_ID;
      const { error } = await supabase.from("usage_logs").upsert(
        records.map((record) => ({
          id: record.id,
          owner_id: ownerId,
          order_id: record.orderId || null,
          order_item_id: record.orderItemId || null,
          item_name_snapshot: record.itemName,
          used_amount: record.usedAmount,
          unit: record.unit,
          inventory_item_id: record.inventoryItemId ?? null,
        })),
        { onConflict: "id" },
      );
      if (error) throw new Error(`Unable to save usage logs: ${error.message}`);
    }

    if (memoryStore) {
      const byId = new Map(memoryStore.usageLogs.map((record) => [record.id, record]));
      for (const record of records) byId.set(record.id, record);
      memoryStore.usageLogs = [...byId.values()];
    }
  });
}

export function updateStore(
  fn: (store: StoreData) => void,
): Promise<StoreData> {
  // writeStore() upserts whole arrays back, so a mutation must always start
  // from a fresh read - applying it to a cached snapshot could silently
  // re-upsert a row another instance deleted within the TTL window.
  return withStore(async (store) => {
    fn(store);
    await writeStore(store);
    return store;
  }, { fresh: true });
}

function enqueue<T>(fn: () => Promise<T>): Promise<T> {
  const ownerIdPromise = activeOwnerId();
  const run = queue.then(async () => {
    const ownerId = await ownerIdPromise;
    const cached = tenantStoreCache.get(ownerId ?? GLOBAL_STORE_KEY);
    if (cached) {
      memoryStore = cached.store;
      memoryStoreReadAt = cached.readAt;
    } else {
      await readStore({ ownerId, fresh: true });
    }
    return fn();
  });
  queue = run.then(
    () => undefined,
    () => undefined,
  );
  return run;
}

// Targeted delete helpers -------------------------------------------------
//
// writeStore() only ever upserts/inserts, so "filter the array, then call
// writeStore()" can never remove a row from Supabase - the row survives and
// reappears on the next cold read. These helpers issue the actual DELETE
// and update memoryStore in place so a deleted row can't be re-upserted by
// another in-flight updateStore() call for the rest of this process's
// lifetime. Each one runs through the same `queue` as withStore(), so it
// can't race a concurrent read-modify-write.
//
// The FK behavior noted in each comment below was verified empirically
// against the live Supabase schema (insert a disposable referencing row,
// attempt the delete, observe the result, clean up) since no migration
// file exists in this repo to read it from.

export async function deleteOrderRecord(id: string): Promise<void> {
  await deleteOrderAtomic(id);
}

export async function deleteRestockRecord(id: string): Promise<void> {
  // Route through delete_restock_atomic so this legacy path also reverses
  // stock from the persisted row instead of dropping the reversal entirely.
  await deleteRestockAtomic({ id });
  if (memoryStore) {
    memoryStore.restocks = memoryStore.restocks.filter((record) => record.id !== id);
  }
}

// Phase 8: atomic multi-table operations -----------------------------------
//
// Each of these calls a single Postgres function (see
// supabase/migrations/20260917061450_atomicity_hardening.sql) so the write
// either fully succeeds or fully rolls back - no manual TypeScript rollback,
// no partial order/inventory/usage-log state.
//
// Cache strategy: order creation patches memoryStore with the exact values
// that were just atomically committed (known with certainty, since the RPC
// is all-or-nothing) rather than invalidating, specifically so printJobs -
// which have no backing table and only ever live in memoryStore - survive
// long enough for the immediately-following print flow to use them. Void/
// delete/restock/rename are lower-frequency admin operations whose exact
// resulting state (e.g. how much inventory a void restores) isn't already
// known on the TypeScript side without an extra read, so those invalidate
// memoryStore instead of risking a hand-patched value drifting from what
// the transaction actually committed.

export async function appendPrintJobs(jobs: PrintJob[]): Promise<void> {
  if (jobs.length === 0) return;
  await enqueue(async () => {
    if (memoryStore) memoryStore.printJobs.push(...jobs);
  });
}

export async function createOrderAtomic(input: {
  order: Order;
  deductions: { inventoryItemId: string; itemName: string; amount: number; unit: string; orderItemId?: string }[];
  voidedBy?: string | null;
}): Promise<{ ok: true; ticketNo: string } | { ok: false; error: string }> {
  return enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (!memoryStore) memoryStore = normalizeStore(emptyStore());
      const { order, deductions } = input;
      const memoryOwnerId = await activeOwnerId();
      let promoEntry: PromotionCode | undefined;
      let promoOwner: StaffUser | undefined;
      if (order.promoLabel) {
        promoOwner = memoryStore.users.find((user) => user.id === memoryOwnerId && user.role === "cashier");
        const permissions = promoOwner?.permissions;
        promoEntry = permissions?.promoCodes?.find((entry) => entry.code === order.promoLabel?.toUpperCase());
        if (!promoOwner || permissions?.promotionsEnabled !== true || permissions.promotionDiscount !== true || !promoEntry) {
          return { ok: false, error: "Invalid promotion code." };
        }
        if (promoEntry.redeemedAt) return { ok: false, error: "The promotion code already used." };
        if (promoEntry.expiresAt && Date.parse(promoEntry.expiresAt) <= Date.now()) {
          return { ok: false, error: "This promo voucher has expired." };
        }
        const selectedLine = Number.isInteger(order.promoItemIndex)
          ? order.items[order.promoItemIndex!]
          : undefined;
        const freeItemQty = Math.max(1, Math.floor(promoEntry.discountValue || 1));
        const expectedDiscount = promoEntry.discountType === "item"
          ? selectedLine && order.promoItemQty === freeItemQty && freeItemQty <= selectedLine.qty
            ? Math.round((selectedLine.price + (selectedLine.addons ?? []).reduce((sum, addon) => sum + addon.price * addon.qty, 0)) * freeItemQty)
            : -1
          : Math.min(
              order.subtotal ?? order.total,
              Math.round(promoEntry.discountType === "amount"
                ? promoEntry.discountValue
                : (order.subtotal ?? order.total) * promoEntry.discountValue / 100),
            );
        if ((order.discount ?? 0) !== expectedDiscount) {
          return { ok: false, error: "Promotion discount does not match this code." };
        }
      }
      if (order.voided && !order.voidedByName && input.voidedBy) {
        order.voidedByName = memoryStore.users.find((user) => user.id === input.voidedBy)?.name;
      }
      for (const deduction of deductions) {
        const item = memoryStore.inventory.find((entry) => entry.id === deduction.inventoryItemId);
        if (item && item.stock < deduction.amount) {
          return { ok: false, error: `Not enough ${deduction.itemName} in stock.` };
        }
      }
      if (promoEntry && promoOwner) {
        const redeemedPromo = { ...promoEntry, redeemedAt: new Date().toISOString(), redeemedOrderId: order.id };
        promoOwner.permissions = {
          ...promoOwner.permissions!,
          promoCodes: promoOwner.permissions!.promoCodes!.map((entry) => entry.code === promoEntry!.code ? redeemedPromo : entry),
        };
      }
      if (!order.ticketNo) {
        order.ticketNo = `#${nextTicketNo(memoryStore.orders, new Date(order.createdAt))}`;
      }
      memoryStore.orders.push(order);
      for (const deduction of deductions) {
        const item = memoryStore.inventory.find((entry) => entry.id === deduction.inventoryItemId);
        if (item) item.stock = Math.max(0, roundQty(item.stock - deduction.amount));
      }
      const now = memoryStore.usageLogs.filter((entry) => entry.orderId !== order.id);
      for (const deduction of deductions) {
        now.push({
          id: `${order.id}-${deduction.inventoryItemId}-usage`,
          orderId: order.id,
          orderItemId: deduction.orderItemId ?? "",
          inventoryItemId: deduction.inventoryItemId,
          date: order.createdAt,
          itemName: deduction.itemName,
          usedAmount: deduction.amount,
          unit: deduction.unit,
        });
      }
      memoryStore.usageLogs = now;
      return { ok: true, ticketNo: order.ticketNo };
    }
    const supabase = supabaseAdmin();
    const { order, deductions } = input;
    const ownerId = await activeOwnerId() ?? POS_STATE_ID;
    const rpcArgs = {
      p_order_id: order.id,
      p_created_at: order.createdAt,
      p_barista_name: order.baristaName,
      p_barista_user_id: order.baristaUserId ?? null,
      p_items: order.items,
      p_subtotal: order.subtotal ?? order.total,
      p_discount: order.discount ?? 0,
      p_promo_id: null,
      p_promo_label: order.promoLabel ?? null,
      p_total: order.total,
      p_payment_method: order.paymentMethod ?? "cash",
      // The RPC allocates the ticket number itself on a per-PH-day counter;
      // p_ticket_no is ignored. The assigned number comes back in the result.
      p_ticket_no: null,
      p_paid: order.paid ?? order.total,
      p_change: order.change ?? 0,
      p_deductions: deductions,
      p_voided: order.voided ?? false,
      p_void_reason: order.voidReason ?? null,
      p_voided_by: input.voidedBy ?? null,
    };
    const promoRpcArgs = order.promoLabel
      ? { p_promo_code: order.promoLabel, p_promo_item_index: order.promoItemIndex ?? null }
      : {};
    const rpcName = order.promoLabel ? "create_order_with_promo_for_owner_atomic" : "create_order_for_owner_atomic";
    let { data, error } = await supabase.rpc(rpcName, { p_owner_id: ownerId, ...promoRpcArgs, ...rpcArgs });
    if (
      error?.code === "23503" &&
      error.message.includes("orders_barista_user_id_fkey")
    ) {
      ({ data, error } = await supabase.rpc(rpcName, {
        p_owner_id: ownerId,
        ...promoRpcArgs,
        ...rpcArgs,
        p_barista_user_id: null,
      }));
    }
    if (error) {
      if (error.message.includes("PROMO_ALREADY_USED")) {
        return { ok: false, error: "The promotion code already used." };
      }
      if (error.message.includes("PROMO_EXPIRED")) {
        return { ok: false, error: "This promo voucher has expired." };
      }
      if (error.message.includes("PROMO_INVALID")) {
        return { ok: false, error: "Invalid promotion code." };
      }
      const insufficient = /INSUFFICIENT_STOCK:(.+)/.exec(error.message);
      if (insufficient) return { ok: false, error: `Not enough ${insufficient[1]} in stock.` };
      throw new Error(`Unable to create order: ${error.message}`);
    }
    if (data?.ticketNo) order.ticketNo = data.ticketNo;
    if (memoryStore) {
      memoryStore.orders.push(order);
      for (const deduction of deductions) {
        const item = memoryStore.inventory.find((entry) => entry.id === deduction.inventoryItemId);
        if (item) item.stock = Math.max(0, roundQty(item.stock - deduction.amount));
      }
      const now = memoryStore.usageLogs.filter((entry) => entry.orderId !== order.id);
      for (const deduction of deductions) {
        now.push({
          id: `${order.id}-${deduction.inventoryItemId}-usage`,
          orderId: order.id,
          orderItemId: deduction.orderItemId ?? "",
          inventoryItemId: deduction.inventoryItemId,
          date: order.createdAt,
          itemName: deduction.itemName,
          usedAmount: deduction.amount,
          unit: deduction.unit,
        });
      }
      memoryStore.usageLogs = now;
    }
    return { ok: true, ticketNo: data?.ticketNo ?? "" };
  });
}

export async function voidOrderAtomic(
  orderId: string,
  reason: string,
  voidedBy: string | null,
): Promise<{ ok: true } | { ok: false; error: string }> {
  return enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (!memoryStore) memoryStore = normalizeStore(emptyStore());
      const order = memoryStore.orders.find((o) => o.id === orderId);
      if (!order) return { ok: false, error: "Ticket not found." };
      if (order.voided) return { ok: false, error: "Ticket is already voided." };
      order.voided = true;
      order.voidReason = reason;
      order.voidedBy = voidedBy ?? undefined;
      order.voidedByName = memoryStore.users.find((user) => user.id === voidedBy)?.name;
      const logs = memoryStore.usageLogs.filter((entry) => entry.orderId === orderId);
      for (const log of logs) {
        const item = memoryStore.inventory.find((entry) => entry.id === log.inventoryItemId || entry.name === log.itemName);
        if (item) item.stock = roundQty(item.stock + log.usedAmount);
      }
      const updatedAt = new Date().toISOString();
      for (const job of memoryStore.printJobs) {
        if (job.orderId === orderId && (job.status === "pending" || job.status === "failed")) {
          job.status = "cancelled";
          job.updatedAt = updatedAt;
          job.lastError = "Order was voided.";
        }
      }
      return { ok: true };
    }
    const supabase = supabaseAdmin();
    const ownerId = await activeOwnerId() ?? POS_STATE_ID;
    const { data, error } = await supabase.rpc("void_order_for_owner_atomic", {
      p_owner_id: ownerId,
      p_order_id: orderId,
      p_reason: reason,
      p_voided_by: voidedBy,
    });
    if (error) throw new Error(`Unable to void order: ${error.message}`);
    if (!data?.ok) {
      return {
        ok: false,
        error: data?.error === "ALREADY_VOIDED" ? "Ticket is already voided." : "Ticket not found.",
      };
    }
    // printJobs has no backing table, so cancel matching pending/failed jobs
    // here (same behavior as the old markOrderVoided) before the
    // memoryStore invalidation below would otherwise silently drop it.
    if (memoryStore) {
      const updatedAt = new Date().toISOString();
      for (const job of memoryStore.printJobs) {
        if (job.orderId === orderId && (job.status === "pending" || job.status === "failed")) {
          job.status = "cancelled";
          job.updatedAt = updatedAt;
          job.lastError = "Order was voided.";
        }
      }
    }
    // Inventory restoration amounts are server-computed from usage_logs;
    // invalidate rather than recompute the same lookup a second time here.
    invalidateStoreCache();
    return { ok: true };
  });
}

export async function deleteOrderAtomic(orderId: string): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (memoryStore) {
        const order = memoryStore.orders.find((o) => o.id === orderId);
        if (order && !order.voided) {
          const logs = memoryStore.usageLogs.filter((entry) => entry.orderId === orderId);
          for (const log of logs) {
            const item = memoryStore.inventory.find((entry) => entry.id === log.inventoryItemId || entry.name === log.itemName);
            if (item) item.stock = roundQty(item.stock + log.usedAmount);
          }
        }
        memoryStore.orders = memoryStore.orders.filter((o) => o.id !== orderId);
        memoryStore.usageLogs = memoryStore.usageLogs.filter((entry) => entry.orderId !== orderId);
        memoryStore.printJobs = memoryStore.printJobs.filter((job) => job.orderId !== orderId);
      }
      return;
    }
    const supabase = supabaseAdmin();
    const ownerId = await activeOwnerId() ?? POS_STATE_ID;
    const { data, error } = await supabase.rpc("delete_order_for_owner_atomic", { p_owner_id: ownerId, p_order_id: orderId });
    if (error) throw new Error(`Unable to delete order: ${error.message}`);
    if (!data?.ok) {
      throw new Error(
        data?.error === "ORDER_NOT_FOUND"
          ? "Unable to delete order: transaction not found."
          : "Unable to delete order: the database did not confirm the deletion.",
      );
    }
    invalidateStoreCache();
  });
}

export async function createRestockAtomic(input: {
  id: string;
  inventoryItemId: string | null;
  itemNameSnapshot: string;
  quantityAdded: number;
  createdAt: string;
  purchaseQty?: number | null;
  purchaseUnit?: string | null;
}): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (!memoryStore) memoryStore = normalizeStore(emptyStore());
      memoryStore.restocks.unshift({
        id: input.id,
        inventoryItemId: input.inventoryItemId ?? undefined,
        itemName: input.itemNameSnapshot,
        quantityAdded: input.quantityAdded,
        purchaseQty: input.purchaseQty ?? undefined,
        purchaseUnit: input.purchaseUnit ?? undefined,
        date: input.createdAt,
      });
      if (input.inventoryItemId) {
        const item = memoryStore.inventory.find((entry) => entry.id === input.inventoryItemId);
        if (item) item.stock = roundQty(item.stock + input.quantityAdded);
      }
      return;
    }
    const supabase = supabaseAdmin();
    const ownerId = await activeOwnerId() ?? POS_STATE_ID;
    const { error } = await supabase.rpc("create_restock_for_owner_atomic", {
      p_owner_id: ownerId,
      p_id: input.id,
      p_inventory_item_id: input.inventoryItemId,
      p_item_name_snapshot: input.itemNameSnapshot,
      p_quantity_added: input.quantityAdded,
      p_created_at: input.createdAt,
      p_purchase_qty: input.purchaseQty ?? null,
      p_purchase_unit: input.purchaseUnit ?? null,
    });
    if (error) throw new Error(`Unable to create restock: ${error.message}`);
    invalidateStoreCache();
  });
}

export async function editRestockAtomic(input: {
  id: string;
  oldInventoryItemId: string | null;
  oldQuantity: number;
  newInventoryItemId: string | null;
  newItemNameSnapshot: string;
  newQuantity: number;
  newCreatedAt: string;
  newPurchaseQty?: number | null;
  newPurchaseUnit?: string | null;
}): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (!memoryStore) memoryStore = normalizeStore(emptyStore());
      if (input.oldInventoryItemId) {
        const oldItem = memoryStore.inventory.find((entry) => entry.id === input.oldInventoryItemId);
        if (oldItem) oldItem.stock = Math.max(0, roundQty(oldItem.stock - input.oldQuantity));
      }
      if (input.newInventoryItemId) {
        const newItem = memoryStore.inventory.find((entry) => entry.id === input.newInventoryItemId);
        if (newItem) newItem.stock = roundQty(newItem.stock + input.newQuantity);
      }
      const existing = memoryStore.restocks.find((r) => r.id === input.id);
      if (existing) {
        existing.inventoryItemId = input.newInventoryItemId ?? undefined;
        existing.itemName = input.newItemNameSnapshot;
        existing.quantityAdded = input.newQuantity;
        existing.purchaseQty = input.newPurchaseQty ?? undefined;
        existing.purchaseUnit = input.newPurchaseUnit ?? undefined;
        existing.date = input.newCreatedAt;
      }
      return;
    }
    const supabase = supabaseAdmin();
    const ownerId = await activeOwnerId() ?? POS_STATE_ID;
    const { error } = await supabase.rpc("edit_restock_for_owner_atomic", {
      p_owner_id: ownerId,
      p_id: input.id,
      p_old_inventory_item_id: input.oldInventoryItemId,
      p_old_quantity: input.oldQuantity,
      p_new_inventory_item_id: input.newInventoryItemId,
      p_new_item_name_snapshot: input.newItemNameSnapshot,
      p_new_quantity: input.newQuantity,
      p_new_created_at: input.newCreatedAt,
      p_new_purchase_qty: input.newPurchaseQty ?? null,
      p_new_purchase_unit: input.newPurchaseUnit ?? null,
    });
    if (error) throw new Error(`Unable to edit restock: ${error.message}`);
    invalidateStoreCache();
  });
}

export async function deleteRestockAtomic(input: { id: string }): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (memoryStore) {
        const existing = memoryStore.restocks.find((r) => r.id === input.id);
        if (existing && existing.inventoryItemId) {
          const item = memoryStore.inventory.find((entry) => entry.id === existing.inventoryItemId);
          if (item) item.stock = Math.max(0, roundQty(item.stock - existing.quantityAdded));
        }
        memoryStore.restocks = memoryStore.restocks.filter((r) => r.id !== input.id);
      }
      return;
    }
    const supabase = supabaseAdmin();
    const ownerId = await activeOwnerId() ?? POS_STATE_ID;
    // The persisted restocks row is authoritative for the reversal - the RPC
    // ignores these caller params; nulls are sent only for signature compat.
    const { error } = await supabase.rpc("delete_restock_for_owner_atomic", {
      p_owner_id: ownerId,
      p_id: input.id,
      p_inventory_item_id: null,
      p_quantity_added: null,
    });
    if (error) throw new Error(`Unable to delete restock: ${error.message}`);
    invalidateStoreCache();
  });
}

export async function renameMenuCategoryAtomic(
  fromName: string,
  toName: string,
  type: MenuCategoryType = "other",
): Promise<{ ok: true } | { ok: false; error: string }> {
  return enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (!memoryStore) memoryStore = normalizeStore(emptyStore());
      const fromLower = fromName.trim().toLowerCase();
      const toLower = toName.trim().toLowerCase();
      if (!memoryStore.categories.some((c) => c.toLowerCase() === fromLower)) {
        return { ok: false, error: "Category not found." };
      }
      if (toLower !== fromLower && memoryStore.categories.some((c) => c.toLowerCase() === toLower)) {
        return { ok: false, error: "That category is already on the board." };
      }
      memoryStore.categories = memoryStore.categories.map((c) => c.toLowerCase() === fromLower ? toName : c);
      if (memoryStore.categoryTypes) {
        for (const categoryName of Object.keys(memoryStore.categoryTypes)) {
          if (categoryName.trim().toLowerCase() === fromLower) {
            delete memoryStore.categoryTypes[categoryName];
          }
        }
        memoryStore.categoryTypes[toName] = normalizeMenuCategoryType(type);
      }
      for (const item of memoryStore.menu) {
        if (item.category.toLowerCase() === fromLower) {
          item.category = toName;
          item.categoryType = normalizeMenuCategoryType(type);
        }
      }
      return { ok: true };
    }
    const supabase = supabaseAdmin();
    const { data: existingRows, error: lookupError } = await supabase
      .from("menu_categories")
      .select("id, name");
    if (lookupError) throw new Error(`Unable to look up menu categories: ${lookupError.message}`);
    const fromRow = (existingRows ?? []).find(
      (row) => row.name.trim().toLowerCase() === fromName.trim().toLowerCase(),
    );
    if (!fromRow) {
      return { ok: false, error: "Category not found." };
    }

    const { error } = await supabase
      .from("menu_categories")
      .update({
        name: toName,
        type: normalizeMenuCategoryType(type),
      })
      .eq("id", fromRow.id);

    if (error) throw new Error(`Unable to rename category: ${error.message}`);
    invalidateStoreCache();
    return { ok: true };
  });
}

export async function deleteInventoryItemRecord(
  id: string,
): Promise<{ error: string } | { ok: true }> {
  return enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (!memoryStore) memoryStore = normalizeStore(emptyStore());
      for (const recipe of Object.values(memoryStore.recipes)) {
        if (Array.isArray(recipe) && recipe.some((ing) => ing.inventoryItemId === id)) {
          return { error: "This item is used in a recipe. Remove it from the recipe before deleting it." };
        }
      }
      for (const rc of memoryStore.recipeCostings) {
        if (rc.ingredients.some((ing) => ing.inventoryItemId === id)) {
          return { error: "This item is used in a recipe. Remove it from the recipe before deleting it." };
        }
      }
      memoryStore.inventory = memoryStore.inventory.filter((item) => item.id !== id);
      return { ok: true };
    }
    const supabase = supabaseAdmin();
    const ownerId = await activeOwnerId() ?? POS_STATE_ID;
    // recipes.inventory_item_id -> inventory_items.id is ON DELETE CASCADE
    // in the live schema, but we don't rely on that: guard explicitly so a
    // referenced item is never silently dropped out of a recipe.
    // recipe_costing_ingredients.inventory_item_id is ON DELETE SET NULL, so
    // the ingredient row itself would survive, but its inventory link (and
    // therefore its stock deduction on order) would silently disappear -
    // guard that too rather than let a recipe costing quietly degrade.
    const [legacyRecipeRefs, recipeCostingIngredientRefs] = await Promise.all([
      supabase.from("recipes").select("id").eq("inventory_item_id", id).eq("owner_id", ownerId).limit(1),
      supabase.from("recipe_costing_ingredients").select("id").eq("inventory_item_id", id).eq("owner_id", ownerId).limit(1),
    ]);
    if (legacyRecipeRefs.error) {
      throw new Error(`Unable to check inventory references: ${legacyRecipeRefs.error.message}`);
    }
    if (recipeCostingIngredientRefs.error) {
      throw new Error(`Unable to check inventory references: ${recipeCostingIngredientRefs.error.message}`);
    }
    if ((legacyRecipeRefs.data && legacyRecipeRefs.data.length > 0) || (recipeCostingIngredientRefs.data && recipeCostingIngredientRefs.data.length > 0)) {
      return { error: "This item is used in a recipe. Remove it from the recipe before deleting it." };
    }

    const { error } = await supabase.from("inventory_items").delete().eq("id", id).eq("owner_id", ownerId);
    if (error) {
      if (/foreign key/i.test(error.message)) {
        return { error: "This item is used in a recipe costing and cannot be deleted." };
      }
      throw new Error(`Unable to delete inventory item: ${error.message}`);
    }
    if (memoryStore) {
      memoryStore.inventory = memoryStore.inventory.filter((item) => item.id !== id);
    }
    return { ok: true };
  });
}

export async function deleteMenuItemRecord(id: string): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (memoryStore) {
        memoryStore.menu = memoryStore.menu.filter((item) => item.id !== id);
      }
      return;
    }
    const supabase = supabaseAdmin();
    const ownerId = await activeOwnerId() ?? POS_STATE_ID;
    // Detach historical order rows first. Their name/price/product snapshots
    // remain intact, and this also works if the deployed FK still uses RESTRICT.
    const { error: detachError } = await supabase
      .from("order_items")
      .update({ menu_item_id: null })
      .eq("menu_item_id", id)
      .eq("owner_id", ownerId);
    if (detachError) {
      throw new Error(`Unable to unlink menu item from past orders: ${detachError.message}`);
    }
    const { error } = await supabase.from("menu_items").delete().eq("id", id).eq("owner_id", ownerId);
    if (error) throw new Error(`Unable to delete menu item: ${error.message}`);
    if (memoryStore) {
      memoryStore.menu = memoryStore.menu.filter((item) => item.id !== id);
    }
  });
}

export async function deleteMenuCategoryRecord(name: string): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (memoryStore) {
        memoryStore.categories = memoryStore.categories.filter(
          (entry) => entry.toLowerCase() !== name.toLowerCase(),
        );
      }
      return;
    }
    const supabase = supabaseAdmin();
    const ownerId = await activeOwnerId() ?? POS_STATE_ID;
    // menu_items.category_id -> menu_categories.id is ON DELETE RESTRICT.
    // The caller already checks for in-use categories before calling this;
    // this is a defensive backstop against a concurrent add.
    const { error } = await supabase.from("menu_categories").delete().ilike("name", name).eq("owner_id", ownerId);
    if (error) throw new Error(`Unable to delete menu category: ${error.message}`);
    if (memoryStore) {
      memoryStore.categories = memoryStore.categories.filter(
        (entry) => entry.toLowerCase() !== name.toLowerCase(),
      );
    }
  });
}

// Menu items/categories are persisted through the targeted helpers below,
// never through writeStore's whole-array upserts - a stale StoreData
// snapshot must not be able to re-insert a deleted row (KAN-123).
async function ensureMenuCategoryId(
  supabase: ReturnType<typeof supabaseAdmin>,
  name: string,
  type: MenuCategoryType = "other",
): Promise<string> {
  const trimmed = name.trim();
  const ownerId = await activeOwnerId() ?? POS_STATE_ID;
  const { data: existing, error: lookupError } = await supabase
    .from("menu_categories")
    .select("id, name, type")
    .eq("owner_id", ownerId);
  if (lookupError) {
    throw new Error(`Unable to read menu categories: ${lookupError.message}`);
  }
  const found = (existing ?? []).find(
    (row) => row.name.trim().toLowerCase() === trimmed.toLowerCase(),
  );
  if (found) return found.id;

  const id = `${ownerId}--${trimmed.toLowerCase().replace(/[^a-z0-9]+/g, "-") || "other"}`;
  const { error } = await supabase
    .from("menu_categories")
    .insert({ id, owner_id: ownerId, name: trimmed, type: normalizeMenuCategoryType(type) });
  if (error) {
    // Another instance may have created it between the lookup and insert.
    const { data: retry } = await supabase
      .from("menu_categories")
      .select("id, name")
      .eq("owner_id", ownerId);
    const retryFound = (retry ?? []).find(
      (row) => row.name.trim().toLowerCase() === trimmed.toLowerCase(),
    );
    if (retryFound) return retryFound.id;
    throw new Error(`Unable to create menu category: ${error.message}`);
  }
  if (
    memoryStore &&
    !memoryStore.categories.some(
      (entry) => entry.toLowerCase() === trimmed.toLowerCase(),
    )
  ) {
    memoryStore.categories.push(trimmed);
  }
  return id;
}

export async function upsertMenuItemRecord(item: MenuItem): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (!memoryStore) memoryStore = normalizeStore(emptyStore());
      if (!memoryStore.categories.some((c) => c.toLowerCase() === item.category.toLowerCase())) {
        memoryStore.categories.push(item.category);
      }
      item.categoryType = normalizeMenuCategoryType(
        item.categoryType ?? memoryStore.categoryTypes?.[item.category] ?? inferMenuCategoryType(item.category),
      );
      const index = memoryStore.menu.findIndex((entry) => entry.id === item.id);
      if (index >= 0) memoryStore.menu[index] = { ...item };
      else memoryStore.menu.push({ ...item });
      return;
    }
    const supabase = supabaseAdmin();
    const categoryType = normalizeMenuCategoryType(
      item.categoryType ?? inferMenuCategoryType(item.category),
    );
    const categoryId = await ensureMenuCategoryId(supabase, item.category, categoryType);
    const itemWithType = { ...item, categoryType };
    const { error } = await supabase.from("menu_items").upsert(
      {
        id: item.id,
        owner_id: await activeOwnerId() ?? POS_STATE_ID,
        name: item.name,
        price: Math.round(item.price),
        category_id: categoryId,
        image: stripMenuImage(item.image),
        available: item.available,
        types: normalizeMenuTypes(item),
        styles: normalizeMenuStyles(item),
        addons: normalizeMenuAddons(item),
      },
      { onConflict: "id" },
    );
    if (error) throw new Error(`Unable to save menu item: ${error.message}`);
    if (memoryStore) {
      const index = memoryStore.menu.findIndex((entry) => entry.id === item.id);
      if (index >= 0) memoryStore.menu[index] = itemWithType;
      else memoryStore.menu.push(itemWithType);
    }
  });
}

export async function insertMenuCategoryRecord(
  name: string,
  type: MenuCategoryType = "other",
): Promise<{ ok: true } | { ok: false; error: string }> {
  return enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (!memoryStore) memoryStore = normalizeStore(emptyStore());
      const trimmed = name.trim();
      if (memoryStore.categories.some((c) => c.toLowerCase() === trimmed.toLowerCase())) {
        return { ok: false, error: "That category is already on the board." };
      }
      memoryStore.categories.push(trimmed);
      if (memoryStore.categoryTypes) {
        memoryStore.categoryTypes[trimmed] = normalizeMenuCategoryType(type);
      }
      return { ok: true };
    }
    const supabase = supabaseAdmin();
    const trimmed = name.trim();
    const { data: existing, error: lookupError } = await supabase
      .from("menu_categories")
      .select("id, name")
      .eq("owner_id", await activeOwnerId() ?? POS_STATE_ID);
    if (lookupError) {
      throw new Error(`Unable to read menu categories: ${lookupError.message}`);
    }
    const found = (existing ?? []).some(
      (row) => row.name.trim().toLowerCase() === trimmed.toLowerCase(),
    );
    if (found) return { ok: false, error: "That category is already on the board." };

    const ownerId = await activeOwnerId() ?? POS_STATE_ID;
    const id = `${ownerId}--${trimmed.toLowerCase().replace(/[^a-z0-9]+/g, "-") || "other"}`;
    const { error } = await supabase
      .from("menu_categories")
      .insert({ id, owner_id: ownerId, name: trimmed, type: normalizeMenuCategoryType(type) });
    if (error) {
      throw new Error(`Unable to create menu category: ${error.message}`);
    }
    if (
      memoryStore &&
      !memoryStore.categories.some(
        (entry) => entry.toLowerCase() === trimmed.toLowerCase(),
      )
    ) {
      memoryStore.categories.push(trimmed);
    }
    if (memoryStore?.categoryTypes) {
      memoryStore.categoryTypes[trimmed] = normalizeMenuCategoryType(type);
    }
    return { ok: true };
  });
}

export async function setMenuItemAvailableRecord(
  id: string,
  available: boolean,
): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (memoryStore) {
        const item = memoryStore.menu.find((entry) => entry.id === id);
        if (item) item.available = available;
      }
      return;
    }
    const supabase = supabaseAdmin();
    const { error } = await supabase
      .from("menu_items")
      .update({ available })
      .eq("id", id)
      .eq("owner_id", await activeOwnerId() ?? POS_STATE_ID);
    if (error) throw new Error(`Unable to update menu item: ${error.message}`);
    if (memoryStore) {
      const item = memoryStore.menu.find((entry) => entry.id === id);
      if (item) item.available = available;
    }
  });
}

export async function insertOwnerPromotionRecord(
  ownerId: string,
  input: Pick<PromotionCode, "discountType" | "discountValue" | "expiresAt">,
  prefix = "",
): Promise<PromotionCode> {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const normalizedPrefix = prefix.trim().toUpperCase();
  const makeCode = () => `${normalizedPrefix ? `${normalizedPrefix}-` : ""}${Array.from({ length: 6 }, () => alphabet[randomInt(alphabet.length)]).join("")}`;
  if (!isRealSupabaseConfigured()) {
    if (!memoryStore) memoryStore = normalizeStore(emptyStore());
    const owner = memoryStore.users.find((entry) => entry.id === ownerId && entry.role === "cashier");
    if (!owner) throw new Error("Owner account not found.");
    const promoCodes = owner.permissions?.promoCodes ?? [];
    let code = makeCode();
    while (memoryStore.users.some((entry) => entry.permissions?.promoCodes?.some((promo) => promo.code === code))) code = makeCode();
    const promo: PromotionCode = { code, ...input };
    owner.permissions = { ...DEFAULT_STAFF_PERMISSIONS, ...owner.permissions, promoCodes: [...promoCodes, promo] };
    return promo;
  }

  const supabase = supabaseAdmin();
  for (let attempt = 0; attempt < 12; attempt += 1) {
    const promo: PromotionCode = { code: makeCode(), ...input };
    const { error } = await supabase.from("promotions").insert({
      owner_id: ownerId,
      code: promo.code,
      discount_type: promo.discountType,
      discount_value: promo.discountValue,
      expires_at: promo.expiresAt,
    });
    if (!error) return promo;
    if (error.code !== "23505") throw new Error(`Could not generate promotion code: ${error.message}`);
  }
  throw new Error("Could not generate a unique promotion code. Please try again.");
}

export async function deleteOwnerPromotionRecord(ownerId: string, code: string): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (!memoryStore) return;
      const owner = memoryStore.users.find((entry) => entry.id === ownerId && entry.role === "cashier");
      if (owner?.permissions?.promoCodes) {
        owner.permissions.promoCodes = owner.permissions.promoCodes.filter((promo) => promo.code !== code);
      }
      return;
    }

    const { error } = await supabaseAdmin()
      .from("promotions")
      .delete()
      .eq("owner_id", ownerId)
      .eq("code", code);
    if (error) throw new Error(`Could not delete promotion code: ${error.message}`);
  });
}

function communePromotionFromRow(row: Record<string, unknown>): PromotionCode {
  return {
    code: String(row.code),
    discountType: row.discount_type as PromotionCode["discountType"],
    discountValue: Number(row.discount_value),
    expiresAt: typeof row.expires_at === "string" ? row.expires_at : undefined,
    redeemedAt: typeof row.redeemed_at === "string" ? row.redeemed_at : undefined,
    redeemedOrderId: typeof row.redeemed_order_id === "string" ? row.redeemed_order_id : undefined,
  };
}

export async function getCommunePromotionRecords(): Promise<PromotionCode[]> {
  if (!isRealSupabaseConfigured()) return [...memoryCommunePromotions];
  const { data, error } = await supabaseAdmin()
    .from("commune_promotions")
    .select("code,discount_type,discount_value,expires_at,redeemed_at,redeemed_order_id")
    .order("created_at", { ascending: false });
  if (error) throw new Error(`Unable to read Commune promotion codes: ${error.message}`);
  return (data ?? []).map((row) => communePromotionFromRow(row));
}

export async function insertCommunePromotionRecord(
  input: Pick<PromotionCode, "discountType" | "discountValue" | "expiresAt">,
  prefix: string,
): Promise<PromotionCode> {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const makeCode = () => `${prefix}-${Array.from({ length: 6 }, () => alphabet[randomInt(alphabet.length)]).join("")}`;
  if (!isRealSupabaseConfigured()) {
    let promo: PromotionCode;
    do { promo = { code: makeCode(), ...input }; }
    while (memoryCommunePromotions.some((entry) => entry.code === promo.code));
    memoryCommunePromotions = [promo, ...memoryCommunePromotions];
    return promo;
  }

  for (let attempt = 0; attempt < 12; attempt += 1) {
    const promo: PromotionCode = { code: makeCode(), ...input };
    const { error } = await supabaseAdmin().from("commune_promotions").insert({
      code: promo.code,
      discount_type: promo.discountType,
      discount_value: promo.discountValue,
      expires_at: promo.expiresAt,
    });
    if (!error) return promo;
    if (error.code !== "23505") throw new Error(`Could not generate Commune voucher: ${error.message}`);
  }
  throw new Error("Could not generate a unique Commune voucher. Please try again.");
}

export async function deleteCommunePromotionRecord(code: string): Promise<void> {
  if (!isRealSupabaseConfigured()) {
    memoryCommunePromotions = memoryCommunePromotions.filter((promo) => promo.code !== code);
    return;
  }
  const { error } = await supabaseAdmin().from("commune_promotions").delete().eq("code", code);
  if (error) throw new Error(`Could not delete Commune voucher: ${error.message}`);
}

export async function upsertStaffUserRecord(user: StaffUser): Promise<void> {
  await enqueue(async () => {
    const activeOwner = await activeOwnerId();
    const normalized: StaffUser = {
      ...user,
      ownerId: user.role === "cashier" ? user.id : user.role === "admin" ? undefined : activeOwner ?? user.ownerId ?? POS_STATE_ID,
      username: user.username.trim().toLowerCase(),
      name: user.name.trim() || user.username.trim(),
      title: formatDbStaffTitle(user),
    };
    if (!isRealSupabaseConfigured()) {
      if (!memoryStore) memoryStore = normalizeStore(emptyStore());
      const idx = memoryStore.users.findIndex((u) => u.id === normalized.id);
      if (idx >= 0) memoryStore.users[idx] = normalized;
      else memoryStore.users.push(normalized);
      return;
    }
    const supabase = supabaseAdmin();
    const { error } = await supabase.from("staff_users").upsert(
      {
        id: normalized.id,
        owner_id: normalized.role === "admin" ? null : normalized.ownerId ?? POS_STATE_ID,
        username: normalized.username,
        email: normalized.email ?? null,
        password: normalized.password,
        password_changed: Boolean(normalized.passwordChanged),
        permissions: normalized.permissions ?? {},
        name: normalized.name,
        role: normalized.role,
        title: normalized.title,
      },
      { onConflict: "id" },
    );
    if (error) throw new Error(`Unable to save staff user: ${error.message}`);
    const tenantOwnerId = normalized.role === "cashier" ? normalized.id : normalized.ownerId ?? activeOwner ?? POS_STATE_ID;
    const tenantCache = tenantStoreCache.get(tenantOwnerId);
    if (tenantCache) {
      const idx = tenantCache.store.users.findIndex((u) => u.id === normalized.id);
      if (idx >= 0) tenantCache.store.users[idx] = normalized;
      else tenantCache.store.users.push(normalized);
      cacheStore(tenantOwnerId, tenantCache.store);
    }
  });
}

export async function deleteStaffUserRecord(id: string): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (memoryStore) {
        memoryStore.users = memoryStore.users.filter((user) => user.id !== id);
      }
      return;
    }
    const supabase = supabaseAdmin();
    // Some deployed databases still have the older NO ACTION FK on
    // login_activity.user_id. Keep the attendance snapshots, but detach the
    // account reference before deleting the staff row.
    const { error: activityError } = await supabase
      .from("login_activity")
      .update({ user_id: null })
      .eq("user_id", id);
    if (activityError) {
      throw new Error(`Unable to preserve staff login history: ${activityError.message}`);
    }
    const { data: staff, error: staffError } = await supabase
      .from("staff_users")
      .select("name")
      .eq("id", id)
      .maybeSingle();
    if (staffError) throw new Error(`Unable to read staff user: ${staffError.message}`);

    // The deployed orders.staff FKs may still use NO ACTION. Preserve both
    // historical names, then detach both references before deleting the user.
    if (staff?.name) {
      const { error: snapshotError } = await supabase
        .from("orders")
        .update({ voided_by_name: staff.name })
        .eq("voided_by", id)
        .is("voided_by_name", null);
      if (snapshotError) {
        throw new Error(`Unable to preserve void history: ${snapshotError.message}`);
      }
    }
    const { error: cashierSnapshotError } = await supabase
      .from("orders")
      .update({ barista_name: staff?.name ?? "Deleted staff" })
      .eq("barista_user_id", id)
      .is("barista_name", null);
    if (cashierSnapshotError) {
      throw new Error(`Unable to preserve cashier history: ${cashierSnapshotError.message}`);
    }
    const { error: detachVoiderError } = await supabase
      .from("orders")
      .update({ voided_by: null })
      .eq("voided_by", id);
    if (detachVoiderError) {
      throw new Error(`Unable to detach void history: ${detachVoiderError.message}`);
    }
    const { error: detachCashierError } = await supabase
      .from("orders")
      .update({ barista_user_id: null })
      .eq("barista_user_id", id);
    if (detachCashierError) {
      throw new Error(`Unable to detach cashier history: ${detachCashierError.message}`);
    }

    const { error } = await supabase.from("staff_users").delete().eq("id", id);
    if (error) throw new Error(`Unable to delete staff user: ${error.message}`);
    if (memoryStore) {
      memoryStore.users = memoryStore.users.filter((user) => user.id !== id);
    }
  });
}

// recipe_costings / recipe_costing_menu_items / recipe_costing_ingredients -
//
// A save always replaces the full menu-item and ingredient sets for a recipe
// costing, which isn't safe as separate upsert/delete/insert REST calls, so it's a single Postgres
// function call (save_recipe_costing, see
// supabase/migrations/20260917043324_recipe_costing_persistence.sql).

export async function saveRecipeCostingRecord(costing: RecipeCosting): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (!memoryStore) memoryStore = normalizeStore(emptyStore());
      const index = memoryStore.recipeCostings.findIndex((entry) => entry.id === costing.id);
      if (index >= 0) memoryStore.recipeCostings[index] = costing;
      else memoryStore.recipeCostings.push(costing);
      return;
    }
    const supabase = supabaseAdmin();
    const ownerId = await activeOwnerId() ?? POS_STATE_ID;
    const { error } = await supabase.rpc("save_recipe_costing_for_owner", {
      p_owner_id: ownerId,
      p_id: costing.id,
      p_name: costing.name,
      p_hot_cup_inventory_item_id: costing.hotCupInventoryItemId ?? null,
      p_iced_cup_inventory_item_id: costing.icedCupInventoryItemId ?? null,
      p_other_cup_inventory_item_id: costing.otherCupInventoryItemId ?? null,
      p_menu_items: costing.menuItems,
      p_ingredients: costing.ingredients,
    });
    if (error) throw new Error(`Unable to save recipe costing: ${error.message}`);
    if (memoryStore) {
      const index = memoryStore.recipeCostings.findIndex((entry) => entry.id === costing.id);
      if (index >= 0) memoryStore.recipeCostings[index] = costing;
      else memoryStore.recipeCostings.push(costing);
    }
  });
}

export async function deleteRecipeCostingRecord(id: string): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (memoryStore) {
        memoryStore.recipeCostings = memoryStore.recipeCostings.filter((entry) => entry.id !== id);
      }
      return;
    }
    const supabase = supabaseAdmin();
    // recipe_costing_menu_items.recipe_costing_id and
    // recipe_costing_ingredients.recipe_costing_id are both
    // ON DELETE CASCADE on recipe_costings.id, so deleting the parent row
    // alone removes both children, atomically, in one statement.
    const { error } = await supabase.from("recipe_costings").delete().eq("id", id).eq("owner_id", await activeOwnerId() ?? POS_STATE_ID);
    if (error) throw new Error(`Unable to delete recipe costing: ${error.message}`);
    if (memoryStore) {
      memoryStore.recipeCostings = memoryStore.recipeCostings.filter((entry) => entry.id !== id);
    }
  });
}

// login_activity -----------------------------------------------------------
//
// Targeted insert/update/delete, not a blanket rewrite: appendPunch() (in
// actions/users.ts) still mutates the in-memory store.loginActivity array
// synchronously (inside the same updateStore() queue turn as its
// "already clocked in" check), so that race protection is unchanged; these
// helpers are how the resulting entry - or an edit/delete of an existing
// one - actually reaches Supabase.

export async function insertLoginActivityRecord(entry: LoginActivity): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (!memoryStore) memoryStore = normalizeStore(emptyStore());
      if (!Array.isArray(memoryStore.loginActivity)) memoryStore.loginActivity = [];
      if (!memoryStore.loginActivity.some((item) => item.id === entry.id)) {
        memoryStore.loginActivity.unshift(entry);
      }
      return;
    }
    const supabase = supabaseAdmin();
    const ownerId = await activeOwnerId() ?? POS_STATE_ID;
    const activityRow = {
      id: entry.id,
      owner_id: ownerId,
      user_id: entry.userId || null,
      username: entry.username,
      name: entry.name,
      role: entry.role,
      type: entry.type,
      at: entry.at,
    };
    let { error } = await supabase
      .from("login_activity")
      .upsert(activityRow, { onConflict: "id", ignoreDuplicates: true });
    if (
      error?.code === "23503" &&
      error.message.includes("login_activity_user_id_fkey")
    ) {
      ({ error } = await supabase
        .from("login_activity")
        .upsert(
          { ...activityRow, user_id: null },
          { onConflict: "id", ignoreDuplicates: true },
        ));
    }
    if (error) throw new Error(`Unable to record login activity: ${error.message}`);
    if (memoryStore) {
      if (!Array.isArray(memoryStore.loginActivity)) memoryStore.loginActivity = [];
      // appendPunch() may have already pushed this same entry into
      // memoryStore synchronously before this call reaches its turn in the
      // queue; recordAuthActivity() has not, so guard against a duplicate.
      if (!memoryStore.loginActivity.some((item) => item.id === entry.id)) {
        memoryStore.loginActivity.unshift(entry);
      }
    }
  });
}

export async function updateLoginActivityTimeRecord(id: string, at: string): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (memoryStore) {
        const entry = memoryStore.loginActivity.find((item) => item.id === id);
        if (entry) entry.at = at;
      }
      return;
    }
    const supabase = supabaseAdmin();
    const { error } = await supabase.from("login_activity").update({ at }).eq("id", id).eq("owner_id", await activeOwnerId() ?? POS_STATE_ID);
    if (error) throw new Error(`Unable to update login activity: ${error.message}`);
    if (memoryStore) {
      const entry = memoryStore.loginActivity.find((item) => item.id === id);
      if (entry) entry.at = at;
    }
  });
}

export async function deleteLoginActivityRecords(ids: string[]): Promise<void> {
  if (ids.length === 0) return;
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (memoryStore) {
        const idSet = new Set(ids);
        memoryStore.loginActivity = memoryStore.loginActivity.filter((item) => !idSet.has(item.id));
      }
      return;
    }
    const supabase = supabaseAdmin();
    const { error } = await supabase.from("login_activity").delete().in("id", ids).eq("owner_id", await activeOwnerId() ?? POS_STATE_ID);
    if (error) throw new Error(`Unable to delete login activity: ${error.message}`);
    if (memoryStore) {
      const idSet = new Set(ids);
      memoryStore.loginActivity = memoryStore.loginActivity.filter((item) => !idSet.has(item.id));
    }
  });
}

// off_requests ---------------------------------------------------------------
//
// Targeted insert/update/delete, not a blanket rewrite - same reasoning as
// login_activity above.

export async function insertOffRequestRecord(entry: OffRequest): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (!memoryStore) memoryStore = normalizeStore(emptyStore());
      if (!Array.isArray(memoryStore.offRequests)) memoryStore.offRequests = [];
      if (!memoryStore.offRequests.some((item) => item.id === entry.id)) {
        memoryStore.offRequests.unshift(entry);
      }
      return;
    }
    const supabase = supabaseAdmin();
    const ownerId = await activeOwnerId() ?? POS_STATE_ID;
    const { error } = await supabase.from("off_requests").insert({
      id: entry.id,
      owner_id: ownerId,
      user_id: entry.userId,
      name: entry.name,
      date: entry.date,
      reason: entry.reason,
      status: entry.status,
      created_at: entry.createdAt,
    });
    if (error) throw new Error(`Unable to create off request: ${error.message}`);
    if (memoryStore) {
      if (!Array.isArray(memoryStore.offRequests)) memoryStore.offRequests = [];
      if (!memoryStore.offRequests.some((item) => item.id === entry.id)) {
        memoryStore.offRequests.unshift(entry);
      }
    }
  });
}

export async function updateOffRequestStatusRecord(id: string, status: OffRequest["status"]): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (memoryStore) {
        const entry = memoryStore.offRequests.find((item) => item.id === id);
        if (entry) entry.status = status;
      }
      return;
    }
    const supabase = supabaseAdmin();
    const { error } = await supabase.from("off_requests").update({ status }).eq("id", id).eq("owner_id", await activeOwnerId() ?? POS_STATE_ID);
    if (error) throw new Error(`Unable to update off request: ${error.message}`);
    if (memoryStore) {
      const entry = memoryStore.offRequests.find((item) => item.id === id);
      if (entry) entry.status = status;
    }
  });
}

export async function deleteOffRequestRecord(id: string): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (memoryStore) {
        memoryStore.offRequests = memoryStore.offRequests.filter((item) => item.id !== id);
      }
      return;
    }
    const supabase = supabaseAdmin();
    const { error } = await supabase.from("off_requests").delete().eq("id", id).eq("owner_id", await activeOwnerId() ?? POS_STATE_ID);
    if (error) throw new Error(`Unable to delete off request: ${error.message}`);
    if (memoryStore) {
      memoryStore.offRequests = memoryStore.offRequests.filter((item) => item.id !== id);
    }
  });
}

// void_requests ---------------------------------------------------------------
//
// Same targeted-write pattern as off_requests. Supabase is the durable
// source of truth so the approval workflow is visible across server
// instances; memoryStore only mirrors rows for TTL-window consistency.
//
// requested_by_id falls back to the row's own id when the staff account
// was deleted (ON DELETE SET NULL), same rationale as offRequests.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function voidRequestFromRow(row: any): VoidRequest {
  return {
    id: row.id,
    requestedAt: row.requested_at,
    requestedById: row.requested_by_id ?? row.id,
    requestedByName: row.requested_by_name,
    reason: row.reason,
    status: row.status,
    orderId: row.order_id ?? undefined,
    items: Array.isArray(row.items) ? (row.items as OrderItem[]) : [],
    subtotal: Number(row.subtotal),
    discount: Number(row.discount),
    promoLabel: row.promo_label ?? undefined,
    total: Number(row.total),
    paymentMethod: parsePayment(row.payment_method),
    approvedAt: row.approved_at ?? undefined,
    approvedByName: row.approved_by_name ?? undefined,
    processedOrderId: row.processed_order_id ?? undefined,
  };
}

export async function insertVoidRequestRecord(entry: VoidRequest): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (!memoryStore) memoryStore = normalizeStore(emptyStore());
      if (!Array.isArray(memoryStore.voidRequests)) memoryStore.voidRequests = [];
      if (!memoryStore.voidRequests.some((item) => item.id === entry.id)) {
        memoryStore.voidRequests.unshift(entry);
      }
      return;
    }
    const supabase = supabaseAdmin();
    const ownerId = await activeOwnerId() ?? POS_STATE_ID;
    const requestRow = {
      id: entry.id,
      owner_id: ownerId,
      requested_at: entry.requestedAt,
      requested_by_id: entry.requestedById || null,
      requested_by_name: entry.requestedByName,
      reason: entry.reason,
      status: entry.status,
      order_id: entry.orderId ?? null,
      items: entry.items,
      subtotal: entry.subtotal,
      discount: entry.discount,
      promo_label: entry.promoLabel ?? null,
      total: entry.total,
      payment_method: entry.paymentMethod,
    };
    let { error } = await supabase.from("void_requests").insert(requestRow);
    if (
      error?.code === "23503" &&
      error.message.includes("void_requests_requested_by_id_fkey")
    ) {
      ({ error } = await supabase.from("void_requests").insert({
        ...requestRow,
        requested_by_id: null,
      }));
    }
    if (error) throw new Error(`Unable to create void request: ${error.message}`);
    if (memoryStore) {
      if (!Array.isArray(memoryStore.voidRequests)) memoryStore.voidRequests = [];
      if (!memoryStore.voidRequests.some((item) => item.id === entry.id)) {
        memoryStore.voidRequests.unshift(entry);
      }
    }
  });
}

// Direct row read for status polling and approval - deliberately bypasses
// the 5s store cache so a cashier polling on one instance sees an approval
// made on another instance immediately.
export async function getVoidRequestRecord(id: string): Promise<VoidRequest | null> {
  return enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (!memoryStore) memoryStore = normalizeStore(emptyStore());
      const item = memoryStore.voidRequests.find((r) => r.id === id);
      return item ? { ...item } : null;
    }
    const supabase = supabaseAdmin();
    const { data, error } = await supabase
      .from("void_requests")
      .select("*")
      .eq("id", id)
      .eq("owner_id", await activeOwnerId() ?? POS_STATE_ID)
      .maybeSingle();
    if (error) throw new Error(`Unable to read void request: ${error.message}`);
    return data ? voidRequestFromRow(data) : null;
  });
}

// approve_void_request_atomic performs the request status update AND the
// order effect (void existing order / create pre-voided order) in a single
// DB transaction, so the approval cannot partially apply across instances.
export async function approveVoidRequestAtomic(input: {
  requestId: string;
  approvedById: string;
  approvedByName: string;
  newOrderId?: string | null;
}): Promise<{ ok: true; processedOrderId: string } | { ok: false; error: string }> {
  return enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (!memoryStore) memoryStore = normalizeStore(emptyStore());
      const request = memoryStore.voidRequests.find((r) => r.id === input.requestId);
      if (!request) return { ok: false, error: "Void request not found." };
      if (request.status !== "pending") return { ok: false, error: "Void request is already approved." };
      request.status = "approved";
      request.approvedByName = input.approvedByName;
      request.approvedAt = new Date().toISOString();

      let processedOrderId = request.orderId;
      if (request.orderId) {
        const order = memoryStore.orders.find((o) => o.id === request.orderId);
        if (order) {
          order.voided = true;
          order.voidReason = request.reason;
          order.voidedBy = input.approvedById;
          order.voidedByName = input.approvedByName;
          const logs = memoryStore.usageLogs.filter((entry) => entry.orderId === request.orderId);
          for (const log of logs) {
            const item = memoryStore.inventory.find((entry) => entry.id === log.inventoryItemId || entry.name === log.itemName);
            if (item) item.stock = roundQty(item.stock + log.usedAmount);
          }
        }
      } else {
        processedOrderId = input.newOrderId ?? `ord-${Date.now()}`;
        const newOrder: Order = {
          id: processedOrderId,
          createdAt: new Date().toISOString(),
          baristaName: request.requestedByName,
          items: request.items,
          subtotal: request.subtotal,
          discount: request.discount,
          promoLabel: request.promoLabel,
          total: request.total,
          paymentMethod: request.paymentMethod,
          ticketNo: `#${nextTicketNo(memoryStore.orders, new Date())}`,
          paid: 0,
          change: 0,
          voided: true,
          voidedBy: input.approvedById,
          voidedByName: input.approvedByName,
          voidReason: request.reason,
        };
        memoryStore.orders.push(newOrder);
      }
      request.processedOrderId = processedOrderId;
      return { ok: true, processedOrderId: processedOrderId! };
    }
    const supabase = supabaseAdmin();
    const ownerId = await activeOwnerId() ?? POS_STATE_ID;
    const { data, error } = await supabase.rpc("approve_void_request_for_owner_atomic", {
      p_owner_id: ownerId,
      p_request_id: input.requestId,
      p_approved_by_id: input.approvedById,
      p_approved_by_name: input.approvedByName,
      p_new_order_id: input.newOrderId ?? null,
      p_ticket_no: null,
    });
    if (error) throw new Error(`Unable to approve void request: ${error.message}`);
    if (!data?.ok) {
      const code = data?.error;
      return {
        ok: false,
        error:
          code === "ALREADY_APPROVED"
            ? "Void request is already approved."
            : code === "ALREADY_VOIDED"
              ? "Ticket is already voided."
              : "Void request not found.",
      };
    }
    // The RPC changed orders/inventory server-side; invalidate rather than
    // recompute the same lookups locally (same approach as voidOrderAtomic).
    invalidateStoreCache();
    return { ok: true, processedOrderId: data.processedOrderId };
  });
}

export async function deleteVoidRequestRecord(id: string): Promise<void> {
  await enqueue(async () => {
    if (!isRealSupabaseConfigured()) {
      if (memoryStore) {
        memoryStore.voidRequests = memoryStore.voidRequests.filter((item) => item.id !== id);
      }
      return;
    }
    const supabase = supabaseAdmin();
    const { error } = await supabase.from("void_requests").delete().eq("id", id).eq("owner_id", await activeOwnerId() ?? POS_STATE_ID);
    if (error) throw new Error(`Unable to delete void request: ${error.message}`);
    if (memoryStore) {
      memoryStore.voidRequests = memoryStore.voidRequests.filter((item) => item.id !== id);
    }
  });
}

export async function recordAuthActivity(entry: {
  userId: string;
  username: string;
  name: string;
  role: Role;
  type: LoginActivity["type"];
}) {
  if (entry.role === "admin") return;

  await insertLoginActivityRecord({
    id: `auth-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`,
    userId: entry.userId,
    username: entry.username,
    name: entry.name,
    role: entry.role,
    type: entry.type,
    at: new Date().toISOString(),
  });
}
