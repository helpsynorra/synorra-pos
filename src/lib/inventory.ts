import { phDateString, phTimestamp } from "@/lib/datetime";
import { hydrateOrderLine, normalizeMenuAddons, normalizeMenuStyles } from "@/lib/menu";
import type {
  DrinkStyle,
  InventoryItem,
  MenuItem,
  OrderItem,
  RecipeCosting,
  RecipeIngredient,
  StoreData,
} from "@/lib/types";

export function roundQty(value: number): number {
  return Math.round((Number(value) || 0) * 100) / 100;
}

export function formatQty(value: number): string {
  const rounded = roundQty(value);
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(2);
}

function itemKey(name: string) {
  return name.trim().toLowerCase();
}

function cupSizeKey(value: string) {
  const normalized = value.trim().toLowerCase().replace(/[^a-z0-9.]/g, "");
  const match = /(\d+(?:\.\d+)?)(oz|ounce|ounces)?/.exec(normalized);
  if (!match) return normalized;
  const unit = match[2] ? "oz" : /cup/i.test(value) ? "oz" : "";
  return `${Number(match[1])}${unit}`;
}

// Inventory identity is exact-after-normalization only. Substring
// containment leaked usage/restock/costing aggregates between similarly
// named items (e.g. "Milk" vs "Milk Automation - Stock"), so identity
// matching must never use fuzzy containment (KAN-125).
export function itemNameEquals(a: string, b: string) {
  const left = a.trim().toLowerCase().normalize("NFKC").replace(/\s+/g, " ");
  const right = b.trim().toLowerCase().normalize("NFKC").replace(/\s+/g, " ");
  return Boolean(left && left === right);
}

// Ledger rows carry inventory_item_id; legacy rows may not. When the caller
// knows the item's id, the id decides and only id-less rows fall back to an
// exact normalized-name comparison.
export function matchesInventoryRow(
  row: { itemName: string; inventoryItemId?: string },
  item: { name: string; inventoryItemId?: string },
) {
  if (item.inventoryItemId && row.inventoryItemId) {
    return row.inventoryItemId === item.inventoryItemId;
  }
  return itemNameEquals(row.itemName, item.name);
}

export function stockLedgerForDate(input: {
  itemName: string;
  inventoryItemId?: string;
  liveStock: number;
  date: string;
  restocks: { itemName: string; quantityAdded: number; date: string; inventoryItemId?: string }[];
  usages: { itemName: string; usedAmount: number; date: string; inventoryItemId?: string }[];
}): { opening: number; restocked: number; used: number; remaining: number } {
  return stockLedgerForRange({ ...input, from: input.date, to: input.date });
}

export function stockLedgerForRange(input: {
  itemName: string;
  inventoryItemId?: string;
  liveStock: number;
  from: string;
  to: string;
  restocks: { itemName: string; quantityAdded: number; date: string; inventoryItemId?: string }[];
  usages: { itemName: string; usedAmount: number; date: string; inventoryItemId?: string }[];
}): { opening: number; restocked: number; used: number; remaining: number } {
  const from = input.from <= input.to ? input.from : input.to;
  const to = input.from <= input.to ? input.to : input.from;
  const afterEnd = (value: string) => phDateString(value) > to;
  const inRange = (value: string) => {
    const day = phDateString(value);
    return day >= from && day <= to;
  };

  const item = { name: input.itemName, inventoryItemId: input.inventoryItemId };
  const sumRestocks = (
    rows: { itemName: string; quantityAdded: number; date: string; inventoryItemId?: string }[],
    matchesDate: (value: string) => boolean,
  ) =>
    roundQty(
      rows
        .filter((row) => matchesInventoryRow(row, item) && matchesDate(row.date))
        .reduce((sum, row) => sum + (Number(row.quantityAdded) || 0), 0),
    );

  const sumUsages = (
    rows: { itemName: string; usedAmount: number; date: string; inventoryItemId?: string }[],
    matchesDate: (value: string) => boolean,
  ) =>
    roundQty(
      rows
        .filter((row) => matchesInventoryRow(row, item) && matchesDate(row.date))
        .reduce((sum, row) => sum + (Number(row.usedAmount) || 0), 0),
    );

  const restocked = sumRestocks(input.restocks, inRange);
  const used = sumUsages(input.usages, inRange);
  const remaining = roundQty(
    Math.max(0, input.liveStock - sumRestocks(input.restocks, afterEnd) + sumUsages(input.usages, afterEnd)),
  );
  const opening = roundQty(remaining - restocked + used);
  return { opening, restocked, used, remaining };
}

export function remainingForUsages(
  usages: { date: string; itemName: string; usedAmount: number }[],
  restocks: { date: string; itemName: string; quantityAdded: number }[],
  inventory: { name: string; stock: number }[],
): number[] {
  const stock = new Map<string, number>();
  for (const item of inventory) {
    stock.set(itemKey(item.name), item.stock);
  }

  type LedgerEvent =
    | { kind: "usage"; at: string; key: string; qty: number; index: number }
    | { kind: "restock"; at: string; key: string; qty: number; index: number };

  const events: LedgerEvent[] = [];
  usages.forEach((usage, index) => {
    events.push({
      kind: "usage",
      at: usage.date,
      key: itemKey(usage.itemName),
      qty: usage.usedAmount,
      index,
    });
  });
  restocks.forEach((restock, index) => {
    events.push({
      kind: "restock",
      at: restock.date,
      key: itemKey(restock.itemName),
      qty: restock.quantityAdded,
      index: usages.length + index,
    });
  });

  events.sort((a, b) => phTimestamp(b.at) - phTimestamp(a.at) || b.index - a.index);

  const remaining = usages.map(() => 0);
  for (const event of events) {
    const current = stock.get(event.key) ?? 0;
    if (event.kind === "usage") {
      remaining[event.index] = roundQty(Math.max(0, current));
      stock.set(event.key, current + event.qty);
    } else {
      stock.set(event.key, Math.max(0, current - event.qty));
    }
  }
  return remaining;
}

type CupAssignment = Pick<
  RecipeCosting,
  "hotCupInventoryItemId" | "icedCupInventoryItemId" | "otherCupInventoryItemId" | "extraCupInventoryItemIds"
>;

export function configuredCupIds(costings: CupAssignment[] | undefined) {
  const ids = new Set<string>();
  for (const costing of costings ?? []) {
    for (const value of [costing.hotCupInventoryItemId, costing.icedCupInventoryItemId, costing.otherCupInventoryItemId]) {
      const id = String(value ?? "").trim();
      if (id) ids.add(id);
    }
    for (const value of costing.extraCupInventoryItemIds ?? []) {
      const id = String(value ?? "").trim();
      if (id) ids.add(id);
    }
  }
  return ids;
}

export function looksLikeCupItem(
  item: { id?: string; name: string; inventoryType?: string },
  costings?: CupAssignment[],
) {
  if (configuredCupIds(costings).has(String(item.id ?? "").trim())) return true;
  if (item.inventoryType) return item.inventoryType === "cup" || item.inventoryType.startsWith("cup_");
  return /\bcups?\b/i.test(String(item.name ?? "").trim());
}

export function cupForOrderLine(
  inventory: InventoryItem[],
  costing: CupAssignment | undefined,
  style?: DrinkStyle,
) {
  const hotCupId = String(costing?.hotCupInventoryItemId ?? "").trim();
  const icedCupId = String(costing?.icedCupInventoryItemId ?? "").trim();
  const selectedId = style === "hot"
    ? hotCupId
    : style === "iced"
      ? icedCupId
      : hotCupId && !icedCupId
        ? hotCupId
        : icedCupId && !hotCupId
          ? icedCupId
          : costing?.otherCupInventoryItemId;
  const id = String(selectedId ?? "").trim();
  if (!id) return undefined;
  return inventory.find((item) => item.id === id);
}

function addonIngredientsForOrderLine(
  store: Partial<Pick<StoreData, "menu" | "inventory">>,
  line: OrderItem,
): RecipeIngredient[] {
  line = hydrateOrderLine(line);
  const menuItem = (store.menu ?? []).find((item) => item.id === line.productId);
  const catalog = new Map(normalizeMenuAddons(menuItem).map((addon) => [addon.id, addon]));
  const inventory = store.inventory ?? [];

  return (line.addons ?? []).flatMap((selected) => {
    const spec =
      catalog.get(String(selected.id ?? "")) ??
      [...catalog.values()].find((addon) => itemNameEquals(addon.name, selected.name));
    const inventoryItemId = String(spec?.inventoryItemId || selected.inventoryItemId || "").trim();
    const usageAmount = Number(spec?.usageAmount ?? selected.usageAmount) || 0;
    const qty = Math.max(1, Number(selected.qty) || 1);
    const amount = usageAmount * qty;
    if (amount <= 0) return [];

    const stock =
      inventory.find((item) => item.id === inventoryItemId) ??
      inventory.find((item) => itemNameEquals(item.name, spec?.name || selected.name));
    if (!stock) return [];

    return [
      {
        inventoryItemId: stock.id,
        name: stock.name,
        amount,
        unit: (spec?.usageUnit || selected.usageUnit || stock.unit || "").trim() || stock.unit,
      },
    ];
  });
}

export function ingredientsForOrderLine(
  store: Partial<Pick<StoreData, "menu" | "recipes" | "recipeCostings" | "inventory">>,
  line: OrderItem,
): RecipeIngredient[] {
  line = hydrateOrderLine(line);
  const menuItem = (store.menu ?? []).find((item) => item.id === line.productId);
  const names = [line.name, menuItem?.name].filter((value): value is string => Boolean(value));
  const normalizeDrink = (value: string) => value
    .trim()
    .toLowerCase()
    .normalize("NFKC")
    .replace(/[·–—-]?\s*(hot|iced)\s*$/i, "")
    .replace(/\s*\((hot|iced)\)\s*$/i, "")
    .replace(/\s+/g, " ");
  const normalizedNames = new Set(names.map(normalizeDrink));
  const matchesDrink = (drink: string) => {
    const normalizedDrink = normalizeDrink(drink);
    return drink === line.productId || normalizedNames.has(normalizedDrink);
  };
  const recipeCostings = store.recipeCostings ?? [];
  const costing = [...recipeCostings].reverse().find((entry) => entry.menuItems.some(matchesDrink));

  // Configured recipe costings are authoritative; otherwise use the legacy recipe map.
  const baseRecipe = recipeCostings.length > 0
    ? costing?.ingredients ?? []
    : (store.recipes ?? {})[line.productId] ?? Object.entries(store.recipes ?? {}).find(([recipeKey]) => matchesDrink(recipeKey))?.[1] ?? [];

  const inventory = store.inventory ?? [];
  const nameStyle = (value: string): DrinkStyle | undefined => {
    const match = /^\s*(iced|hot)\b/i.exec(value);
    return match ? match[1].toLowerCase() as DrinkStyle : undefined;
  };
  const availableStyles = menuItem ? normalizeMenuStyles(menuItem) : [];
  const inferredStyle = line.style ?? nameStyle(line.name) ?? (availableStyles.length === 1 ? availableStyles[0] : undefined);
  const selectedSize = (line.addons ?? []).find((addon) => addon.id.startsWith("size:") && addon.qty > 0);
  const sizeCup = selectedSize
    ? inventory.find((item) =>
        looksLikeCupItem(item, store.recipeCostings) &&
        (!inferredStyle || !item.inventoryType?.startsWith("cup_") || item.inventoryType === `cup_${inferredStyle}`) &&
        cupSizeKey(item.cupSize ?? item.name) === cupSizeKey(selectedSize.name),
      )
    : undefined;
  const selectedCup = sizeCup ?? cupForOrderLine(inventory, costing, inferredStyle);
  const recipe = selectedCup && costing?.cupRecipes?.[selectedCup.id]
    ? costing.cupRecipes[selectedCup.id]
    : baseRecipe;
  const cupIds = configuredCupIds(store.recipeCostings);
  const isCupIngredient = (ingredient: RecipeIngredient) => {
    if (cupIds.has(ingredient.inventoryItemId)) return true;
    const stock =
      inventory.find((item) => item.id === ingredient.inventoryItemId) ??
      inventory.find((item) => itemNameEquals(item.name, ingredient.name));
    return stock
      ? looksLikeCupItem(stock, store.recipeCostings)
      : looksLikeCupItem({ name: ingredient.name }, store.recipeCostings);
  };
  const resolvedRecipe = recipe.filter((ingredient) => Number(ingredient.amount) > 0).map((ingredient) => {
    if (!selectedCup || !isCupIngredient(ingredient)) return ingredient;
    return { ...ingredient, inventoryItemId: selectedCup.id, name: selectedCup.name, unit: selectedCup.unit };
  });
  const additionalCups = (costing?.extraCupInventoryItemIds ?? [])
    .map((id) => inventory.find((item) => item.id === id))
    .filter((item): item is InventoryItem => Boolean(item));
  const selectedCups = [selectedCup, ...additionalCups].filter(
    (item, index, all): item is InventoryItem => Boolean(item) && all.findIndex((candidate) => candidate?.id === item?.id) === index,
  );
  const cupIngredients = selectedCups
    .filter((cup) => !resolvedRecipe.some((ingredient) => ingredient.inventoryItemId === cup.id))
    .map((cup) => ({ inventoryItemId: cup.id, name: cup.name, amount: 1, unit: cup.unit }));

  return [
    ...resolvedRecipe,
    ...cupIngredients,
    ...addonIngredientsForOrderLine(store, line),
  ];
}

export function recipeForMenuPreview(store: StoreData, item: MenuItem): RecipeIngredient[] {
  return ingredientsForOrderLine(store, {
    productId: item.id,
    name: item.name,
    qty: 1,
    price: item.price,
  });
}
