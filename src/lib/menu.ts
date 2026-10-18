import type { DrinkStyle, MenuAddon, MenuCategoryType, MenuItem, OrderAddon, OrderItem } from "@/lib/types";

export const MENU_IMAGES = [
  { label: "Logo", src: "/images/logo.png" },
] as const;

export const MENU_CATEGORIES = [
  "Non Coffee",
  "Soda Series",
  "Coffee Series",
  "Milky Series",
  "Yogurt Series",
  "Milk Tea Series",
  "Frappe Series",
] as const;

export const DRINK_STYLES: DrinkStyle[] = ["iced", "hot"];

export function normalizeMenuCategoryType(value: unknown): MenuCategoryType {
  const text = typeof value === "string" ? value.trim() : "";
  return text || "other";
}

export function inferMenuCategoryType(category: string): MenuCategoryType {
  const normalized = String(category ?? "").trim().toLowerCase();
  if (/food|meal|snack/i.test(normalized)) return "food";
  if (/pastr|cake|bread|dessert/i.test(normalized)) return "pastry";
  if (/drink|coffee|matcha|tea|juice|smoothie|beverage|fresh|soda|milky|yogurt|frappe|series/i.test(normalized)) return "drink";
  return "other";
}

export function menuCategoryTypeLabel(type: MenuCategoryType) {
  const trimmed = type.trim();
  return trimmed ? trimmed.charAt(0).toUpperCase() + trimmed.slice(1) : "Other";
}

export function isFoodOrPastry(category: string, categoryType?: string) {
  if (typeof categoryType === "string" && categoryType.trim()) {
    const normalizedType = categoryType.trim().toLowerCase();
    return (
      normalizedType === "food" ||
      normalizedType === "foods" ||
      normalizedType === "pastry" ||
      normalizedType === "pastries"
    );
  }
  const type = inferMenuCategoryType(category);
  return type === "food" || type === "pastry";
}

export function drinkStyleLabel(style: DrinkStyle) {
  return style === "hot" ? "Hot" : "Iced";
}

export function normalizeMenuStyles(item: Pick<MenuItem, "category" | "styles" | "categoryType">): DrinkStyle[] {
  if (isFoodOrPastry(item.category, item.categoryType)) return [];
  const raw = Array.isArray(item.styles) ? item.styles : [];
  return DRINK_STYLES.filter((style) => raw.includes(style));
}

export function drinkStyleLabelList(item: Pick<MenuItem, "category" | "styles">) {
  const styles = normalizeMenuStyles(item);
  return styles.length > 0 ? styles.map(drinkStyleLabel).join(" / ") : "—";
}

export function parseDrinkStyle(value: unknown): DrinkStyle | undefined {
  return value === "hot" || value === "iced" ? value : undefined;
}

export function addonIdFromName(name: string, index = 0) {
  const slug = name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return `${slug || "addon"}-${index}`;
}

export function parseStoredOrderAddons(value: unknown): OrderAddon[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry, index) => {
    const row = entry && typeof entry === "object" ? (entry as Record<string, unknown>) : {};
    const name = String(row.name ?? "").trim();
    if (!name) return [];
    const qty = Math.max(1, Math.min(9, Math.floor(Number(row.qty) || 1)));
    const inventoryItemId = String(row.inventoryItemId ?? "").trim();
    const usageAmount = Math.max(0, Number(row.usageAmount) || 0);
    const usageUnit = String(row.usageUnit ?? "").trim();
    return [
      {
        id: String(row.id ?? "").trim() || addonIdFromName(name, index),
        name,
        price: Math.max(0, Math.round(Number(row.price) || 0)),
        qty,
        inventoryItemId: inventoryItemId || undefined,
        usageAmount: usageAmount || undefined,
        usageUnit: usageUnit || undefined,
      },
    ];
  });
}

export function normalizeMenuAddons(item: Pick<MenuItem, "addons"> | undefined): MenuAddon[] {
  if (!Array.isArray(item?.addons)) return [];
  const seen = new Set<string>();
  return item.addons.flatMap((addon, index) => {
    const name = String(addon?.name ?? "").trim();
    if (!name) return [];
    const price = Math.max(0, Math.round(Number(addon.price) || 0));
    let id = String(addon.id ?? "").trim() || addonIdFromName(name, index);
    if (seen.has(id)) id = `${id}-${index}`;
    seen.add(id);
    const inventoryItemId = String(addon.inventoryItemId ?? "").trim();
    const usageAmount = Math.max(0, Number(addon.usageAmount) || 0);
    const usageUnit = String(addon.usageUnit ?? "").trim();
    return [
      {
        id,
        name,
        price,
        qtyEnabled: Boolean(addon.qtyEnabled),
        inventoryItemId: inventoryItemId || undefined,
        usageAmount: usageAmount || undefined,
        usageUnit: usageUnit || undefined,
      },
    ];
  });
}

export function normalizeMenuTypes(item: Pick<MenuItem, "types"> | undefined): string[] {
  if (!Array.isArray(item?.types)) return [];
  const seen = new Set<string>();
  return item.types.flatMap((value) => {
    const name = String(value ?? "").trim();
    const key = name.toLowerCase();
    if (!name || seen.has(key)) return [];
    seen.add(key);
    return [name];
  });
}

// Legacy rows written by another branch embed an options payload after this
// marker in menu_items.image. We never write it, but we strip it on read /
// validation so existing rows render and validate cleanly.
const MENU_IMAGE_OPTIONS_MARK = "#cc-opt=";

export function stripMenuImage(image: string) {
  const value = String(image ?? "");
  const index = value.indexOf(MENU_IMAGE_OPTIONS_MARK);
  return (index >= 0 ? value.slice(0, index) : value) || "/images/logo.png";
}

// Read-side fallback for legacy "#cc-opt=<base64url JSON>" marker rows that
// predate the menu_items.styles/addons columns (the migration decodes all of
// them, but this keeps any straggler readable). Never used on the write path.
export function parseMenuImageOptions(image: string): { styles: DrinkStyle[]; addons: MenuAddon[] } {
  const value = String(image ?? "");
  const index = value.indexOf(MENU_IMAGE_OPTIONS_MARK);
  if (index < 0) return { styles: [], addons: [] };
  try {
    const payload = value.slice(index + MENU_IMAGE_OPTIONS_MARK.length);
    const b64 = payload.replace(/-/g, "+").replace(/_/g, "/");
    const parsed = JSON.parse(atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4)));
    const styles = Array.isArray(parsed?.styles)
      ? parsed.styles.flatMap((style: unknown) => (style === "hot" || style === "iced" ? [style] : []))
      : [];
    return { styles, addons: normalizeMenuAddons({ addons: parsed?.addons }) };
  } catch {
    return { styles: [], addons: [] };
  }
}

export function addonAllowsQty(addon: Pick<MenuAddon, "name" | "qtyEnabled">) {
  return /espresso|shot/i.test(addon.name);
}

export function resolveOrderAddons(
  menuItem: MenuItem,
  selected?: OrderAddon[] | null,
): OrderAddon[] {
  const catalog = new Map(normalizeMenuAddons(menuItem).map((addon) => [addon.id, addon]));
  for (const [index, name] of normalizeMenuTypes(menuItem).entries()) {
    const id = `type:${addonIdFromName(name, index)}`;
    catalog.set(id, { id, name, price: 0 });
  }
  if (!Array.isArray(selected)) return [];
  let typeSelected = false;
  const selections = selected.filter((entry) => {
    const id = String(entry?.id ?? "");
    if (!id.startsWith("type:")) return true;
    if (typeSelected || Number(entry?.qty) <= 0) return false;
    typeSelected = true;
    return true;
  });
  return selections.flatMap((entry) => {
    const addon = catalog.get(String(entry?.id ?? ""));
    if (!addon) return [];
    const qty = Math.max(0, Math.min(9, Math.floor(Number(entry.qty) || 0)));
    if (qty < 1) return [];
    return [{
      id: addon.id,
      name: addon.name,
      price: addon.id.startsWith("size:") ? addon.price - menuItem.price : addon.price,
      qty: addonAllowsQty(addon) ? qty : 1,
      inventoryItemId: addon.inventoryItemId,
      usageAmount: addon.usageAmount,
      usageUnit: addon.usageUnit,
    }];
  });
}

export function addonExtra(addons?: OrderAddon[] | null) {
  return (addons ?? []).reduce((sum, addon) => sum + addon.price * Math.max(1, addon.qty || 1), 0);
}

export function cartLineUnitPrice(item: Pick<OrderItem, "price" | "addons">) {
  return Number(item.price) + addonExtra(item.addons);
}

function addonPriceLabel(addon: OrderAddon) {
  if (addon.id.startsWith("size:")) return addon.name;
  const qty = Math.max(1, addon.qty || 1);
  const name = qty > 1 ? `${qty}× ${addon.name}` : addon.name;
  if (!addon.price) return name;
  return `${name} ₱${addon.price * qty}`;
}

function parseAddonLabels(raw: string): OrderAddon[] {
  return raw.split(/\s*,\s*/).flatMap((part, index) => {
    const text = part.trim();
    if (!text) return [];
    const match = /^(?:(\d+)\s*[×x]\s*)?(.+?)(?:\s*₱\s*(\d+))?$/i.exec(text);
    if (!match) return [];
    const name = match[2].trim();
    if (!name) return [];
    return [
      {
        id: addonIdFromName(name, index),
        name,
        price: match[3] ? Number(match[3]) : 0,
        qty: match[1] ? Math.max(1, Number(match[1])) : 1,
      },
    ];
  });
}

function cleanOrderItemName(name: string) {
  return name
    .replace(/\s*·\s*(Iced|Hot)(?:\s*\+\s*.*)?$/i, "")
    .replace(/\s*\+\s*.+$/, "")
    .replace(/\s*\((iced|hot)\)$/i, "")
    .trim();
}

export function parseOrderItemSnapshot(name: string): {
  name: string;
  style?: DrinkStyle;
  addons: OrderAddon[];
} {
  const raw = String(name ?? "").trim();
  const withAddons = /^(.*?)\s*·\s*(Iced|Hot)\s*\+\s*(.+)$/i.exec(raw);
  if (withAddons) {
    return {
      name: withAddons[1].trim() || raw,
      style: withAddons[2].toLowerCase() === "hot" ? "hot" : "iced",
      addons: parseAddonLabels(withAddons[3]),
    };
  }
  const styleOnly = /^(.*?)\s*·\s*(Iced|Hot)\s*$/i.exec(raw) || /^(.*?)\s*\((Iced|Hot)\)\s*$/i.exec(raw);
  if (styleOnly) {
    return {
      name: styleOnly[1].trim() || raw,
      style: styleOnly[2].toLowerCase() === "hot" ? "hot" : "iced",
      addons: [],
    };
  }
  const addonsOnly = /^(.*?)\s*\+\s*(.+)$/.exec(raw);
  if (addonsOnly && !/^[+\d]/.test(addonsOnly[1].trim())) {
    return {
      name: addonsOnly[1].trim() || raw,
      addons: parseAddonLabels(addonsOnly[2]),
    };
  }
  return { name: raw, addons: [] };
}

export function hydrateOrderLine<T extends Pick<OrderItem, "name" | "style" | "addons">>(item: T): T {
  const parsed = parseOrderItemSnapshot(item.name);
  const style = parseDrinkStyle(item.style) ?? parsed.style;
  const addons = (item.addons ?? []).length > 0 ? item.addons : parsed.addons;
  return {
    ...item,
    name: cleanOrderItemName(item.name) || parsed.name || item.name,
    style,
    addons,
  };
}

export function orderLineOptionsLabel(item: Pick<OrderItem, "style" | "addons" | "name">) {
  const hydrated = hydrateOrderLine(item);
  const parts: string[] = [];
  if (hydrated.style) parts.push(drinkStyleLabel(hydrated.style));
  for (const addon of hydrated.addons ?? []) {
    if (!addon?.name) continue;
    parts.push(addonPriceLabel(addon));
  }
  return parts.join(", ");
}

export function drinkDisplayName(item: Pick<OrderItem, "name" | "style" | "addons">) {
  return hydrateOrderLine(item).name || item.name;
}

export function orderLineListLabel(item: OrderItem) {
  const options = orderLineOptionsLabel(item);
  const name = drinkDisplayName(item);
  return options ? `${name} (${options})` : name;
}

export type OrderSoldLine = {
  title: string;
  detail?: string;
};

export function orderSoldAsParts(items: OrderItem[]): OrderSoldLine[] {
  return items.map((item) => {
    const options = orderLineOptionsLabel(item);
    return {
      title: `${item.qty}x ${drinkDisplayName(item)}`,
      detail: options || undefined,
    };
  });
}

export function orderSoldAsLines(items: OrderItem[]) {
  return orderSoldAsParts(items).map((line) => (line.detail ? `${line.title} (${line.detail})` : line.title));
}

export function orderSoldAsLabel(items: OrderItem[]) {
  return orderSoldAsLines(items).join(", ");
}

export function cartLineKey(item: Pick<OrderItem, "productId" | "style" | "addons">) {
  const addons = (item.addons ?? [])
    .filter((addon) => addon.qty > 0)
    .map((addon) => `${addon.id}:${addon.qty}`)
    .sort()
    .join(",");
  return `${item.productId}|${item.style ?? ""}|${addons}`;
}

export function pricedOrderLine(
  menuItem: MenuItem,
  line: Pick<OrderItem, "qty" | "name" | "style" | "addons">,
): OrderItem {
  const qty = Number(line.qty);
  const style =
    parseDrinkStyle(line.style) ??
    (/·\s*hot$/i.test(line.name) || /\(hot\)$/i.test(line.name)
      ? "hot"
      : /·\s*iced$/i.test(line.name) || /\(iced\)$/i.test(line.name)
        ? "iced"
        : undefined);
  const allowed = normalizeMenuStyles(menuItem);
  const nextStyle = style && allowed.includes(style) ? style : allowed.length === 1 ? allowed[0] : undefined;
  const addons = resolveOrderAddons(menuItem, line.addons);
  return {
    productId: menuItem.id,
    name: menuItem.name,
    qty,
    price: menuItem.price + addonExtra(addons),
    category: menuItem.category,
    style: nextStyle,
    addons,
  };
}

function makeSeriesItems(
  category: string,
  idPrefix: string,
  names: string[],
  sizes: { name: string; price: number }[],
): MenuItem[] {
  return names.map((name) => {
    const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
    return {
      id: `${idPrefix}-${slug}`,
      name,
      price: sizes[0]?.price ?? 0,
      category,
      image: MENU_IMAGES[0].src,
      available: true,
      addons: sizes.map((size) => ({
        id: `size:${size.name.toLowerCase().replace(/[^a-z0-9]+/g, "-")}`,
        name: size.name,
        price: size.price,
      })),
    };
  });
}

export const DEFAULT_MENU: MenuItem[] = [
  ...makeSeriesItems("Non Coffee", "non-coffee", [
    "Iced Matcha", "Iced Milo", "Iced Choco", "Choco Hazel Nut", "Matcha Berry", "Blueberry Matcha",
  ], [{ name: "16oz", price: 50 }, { name: "22oz", price: 70 }]),
  ...makeSeriesItems("Soda Series", "soda", [
    "Green Apple", "Strawberry", "Blueberry", "Mixed Berries", "Lychee",
  ], [{ name: "16oz", price: 50 }, { name: "22oz", price: 70 }]),
  ...makeSeriesItems("Coffee Series", "coffee", [
    "Caramel Macchiato", "Spanish Latte", "Vanilla Latte", "Salted Caramel", "Matcha Latte", "Mocha Latte",
  ], [{ name: "16oz", price: 50 }, { name: "22oz", price: 70 }]),
  ...makeSeriesItems("Milky Series", "milky", [
    "Strawberry Milk", "Strawberry Matcha", "Matcha Oreo", "Cookies & Cream", "Milo Lava", "Choco Berry",
  ], [{ name: "16oz", price: 89 }, { name: "22oz", price: 109 }]),
  ...makeSeriesItems("Yogurt Series", "yogurt", [
    "Strawberry", "Blueberry", "Green Apple", "Mixed Berries",
  ], [{ name: "16oz", price: 50 }, { name: "22oz", price: 70 }]),
  ...makeSeriesItems("Milk Tea Series", "milk-tea", [
    "Brown Sugar Boba", "Okinawa", "Wintermelon", "Dark Choco", "Cookies & Cream",
  ], [{ name: "16oz", price: 60 }, { name: "22oz", price: 80 }]),
  ...makeSeriesItems("Frappe Series", "frappe", [
    "Strawberry Milk", "Matcha", "Matcha Oreo", "Dark Choco Cookies", "Java Chips",
  ], [{ name: "22oz", price: 129 }]),
].map((item) => ({
  ...item,
  image: MENU_IMAGES[0].src,
  styles: [...DRINK_STYLES.slice(0, 1)],
}));

export const MENU = DEFAULT_MENU;

export function formatMoney(amount: number): string {
  return new Intl.NumberFormat("en-PH", {
    style: "currency",
    currency: "PHP",
    maximumFractionDigits: 0,
  }).format(amount);
}

export function menuItemId(name: string): string {
  const slug = name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return `${slug || "item"}-${Date.now().toString(36)}`;
}
