import { expect, test } from "@playwright/test";
import { ingredientsForOrderLine } from "../src/lib/inventory";
import type { InventoryItem, MenuItem, RecipeCosting } from "../src/lib/types";

test("hot size uses its own ingredients and style-matched cup when sizes are duplicated", () => {
  const inventory = [
    {
      id: "beans",
      name: "Coffee Beans",
      unit: "grams",
      stock: 1000,
      cost: 0,
      maxStock: 1000,
      inventoryType: "ingredient",
    },
    {
      id: "milk",
      name: "Milk",
      unit: "ml",
      stock: 1000,
      cost: 0,
      maxStock: 1000,
      inventoryType: "ingredient",
    },
    {
      id: "legacy-22",
      name: "22oz",
      unit: "pcs",
      stock: 100,
      cost: 0,
      maxStock: 100,
      inventoryType: "cup",
      cupSize: "22oz",
    },
    {
      id: "hot-22",
      name: "Hot Cup - 22",
      unit: "pcs",
      stock: 100,
      cost: 0,
      maxStock: 100,
      inventoryType: "cup_hot",
      cupSize: "22oz",
    },
    {
      id: "iced-22",
      name: "Iced Cup - 22",
      unit: "pcs",
      stock: 100,
      cost: 0,
      maxStock: 100,
      inventoryType: "cup_iced",
      cupSize: "22oz",
    },
  ] satisfies InventoryItem[];

  const costing = {
    id: "coffee-costing",
    name: "Iced Coffee",
    menuItems: ["Iced Coffee"],
    ingredients: [
      { inventoryItemId: "beans", name: "Coffee Beans", amount: 3, unit: "grams" },
    ],
    hotCupInventoryItemId: "hot-16",
    icedCupInventoryItemId: "iced-22",
    extraCupInventoryItemIds: ["hot-22"],
    cupRecipes: {
      "hot-22": [
        { inventoryItemId: "beans", name: "Coffee Beans", amount: 8, unit: "grams" },
        { inventoryItemId: "milk", name: "Milk", amount: 130, unit: "ml" },
      ],
    },
  } satisfies RecipeCosting;

  const menuItem = {
    id: "iced-coffee",
    name: "Iced Coffee",
    price: 100,
    category: "Coffee",
    image: "",
    available: true,
    styles: ["hot", "iced"],
    addons: [{ id: "size:22oz", name: "22oz", price: 20 }],
  } satisfies MenuItem;

  const recipe = ingredientsForOrderLine(
    { menu: [menuItem], inventory, recipeCostings: [costing] },
    {
      productId: menuItem.id,
      name: menuItem.name,
      qty: 1,
      price: 120,
      style: "hot",
      addons: [{ id: "size:22oz", name: "22oz", qty: 1, price: 20 }],
    },
  );

  expect(recipe).toEqual(
    expect.arrayContaining([
      expect.objectContaining({ inventoryItemId: "beans", amount: 8 }),
      expect.objectContaining({ inventoryItemId: "milk", amount: 130 }),
      expect.objectContaining({ inventoryItemId: "hot-22", amount: 1 }),
    ]),
  );
  expect(recipe.map((item) => item.inventoryItemId)).not.toContain("legacy-22");
  expect(recipe.map((item) => item.inventoryItemId)).not.toContain("iced-22");
});

test("a drink without a recipe consumes no cup or linked add-on stock", () => {
  const cup: InventoryItem = {
    id: "iced-16",
    name: "Iced Cup - 16",
    unit: "pcs",
    stock: 100,
    cost: 0,
    maxStock: 100,
    inventoryType: "cup_iced",
    cupSize: "16oz",
  };
  const chocolate: MenuItem = {
    id: "chocolate",
    name: "Chocolate",
    price: 150,
    category: "Coffee",
    image: "",
    available: true,
    styles: ["iced"],
    addons: [{
      id: "size:16oz",
      name: "16oz",
      price: 0,
      inventoryItemId: cup.id,
      usageAmount: 1,
      usageUnit: "pcs",
    }],
  };

  const deductions = ingredientsForOrderLine(
    {
      menu: [chocolate],
      inventory: [cup],
      recipeCostings: [{
        id: "coffee-costing",
        name: "Iced Coffee",
        menuItems: ["Iced Coffee"],
        ingredients: [{ inventoryItemId: "beans", name: "Coffee Beans", amount: 3, unit: "grams" }],
      }],
      // Simulate an old legacy row left behind after the menu item stopped
      // having a recipe costing.
      recipes: {
        Chocolate: [{ inventoryItemId: cup.id, name: cup.name, amount: 1, unit: "pcs" }],
      },
    },
    {
      productId: chocolate.id,
      name: chocolate.name,
      qty: 1,
      price: chocolate.price,
      style: "iced",
      addons: [{
        id: "size:16oz",
        name: "16oz",
        qty: 1,
        price: 0,
        inventoryItemId: cup.id,
        usageAmount: 1,
        usageUnit: "pcs",
      }],
    },
  );

  expect(deductions).toEqual([]);

  const staleLegacyRecipeOnly = ingredientsForOrderLine(
    { menu: [chocolate], inventory: [cup], recipeCostings: [], recipes: {
      Chocolate: [{ inventoryItemId: cup.id, name: cup.name, amount: 1, unit: "pcs" }],
    } },
    {
      productId: chocolate.id,
      name: chocolate.name,
      qty: 1,
      price: chocolate.price,
      style: "iced",
      addons: [{
        id: "size:16oz",
        name: "16oz",
        qty: 1,
        price: 0,
        inventoryItemId: cup.id,
        usageAmount: 1,
        usageUnit: "pcs",
      }],
    },
  );
  expect(staleLegacyRecipeOnly).toEqual([]);
});

test("a cup size without its own configured recipe consumes nothing", () => {
  const hot16: InventoryItem = {
    id: "hot-16",
    name: "Hot Cup - 16",
    unit: "pcs",
    stock: 100,
    cost: 0,
    maxStock: 100,
    inventoryType: "cup_hot",
    cupSize: "16oz",
  };
  const hot22: InventoryItem = {
    ...hot16,
    id: "hot-22",
    name: "Hot Cup - 22",
    cupSize: "22oz",
  };
  const coffee: MenuItem = {
    id: "coffee",
    name: "Coffee",
    price: 100,
    category: "Coffee",
    image: "",
    available: true,
    styles: ["hot"],
    addons: [{ id: "size:16oz", name: "16oz", price: 0 }],
  };
  const deductions = ingredientsForOrderLine(
    {
      menu: [coffee],
      inventory: [hot16, hot22],
      recipeCostings: [{
        id: "coffee-costing",
        name: "Coffee",
        menuItems: ["Coffee"],
        // Shared values must not leak into a different size once size-specific
        // recipes have been configured.
        ingredients: [{ inventoryItemId: "beans", name: "Coffee Beans", amount: 5, unit: "grams" }],
        hotCupInventoryItemId: hot16.id,
        cupRecipes: {
          [hot22.id]: [{ inventoryItemId: "beans", name: "Coffee Beans", amount: 8, unit: "grams" }],
        },
      }],
    },
    {
      productId: coffee.id,
      name: coffee.name,
      qty: 1,
      price: coffee.price,
      style: "hot",
      addons: [{ id: "size:16oz", name: "16oz", qty: 1, price: 0 }],
    },
  );

  expect(deductions).toEqual([]);
});
