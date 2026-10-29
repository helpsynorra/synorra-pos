import { expect, test } from "@playwright/test";
import { orderItemCategories, orderItemCategory } from "../src/lib/menu";
import type { MenuItem, OrderItem } from "../src/lib/types";

test("collects order item categories once and preserves configured category labels", () => {
  const menu = [
    { id: "latte", name: "Spanish Latte", category: "Drinks" },
    { id: "cake", name: "Chocolate Cake", category: "Foods" },
    { id: "pastry", name: "Butter Croissant", category: "Pastries" },
  ] satisfies Pick<MenuItem, "id" | "name" | "category">[];
  const items = [
    { productId: "latte", name: "Spanish Latte", qty: 1, price: 150 },
    { productId: "latte", name: "Spanish Latte", qty: 1, price: 150, category: "drinks" },
    { productId: "cake", name: "Chocolate Cake", qty: 1, price: 120 },
    { productId: "pastry", name: "Butter Croissant", qty: 1, price: 90 },
  ] satisfies OrderItem[];

  expect(orderItemCategories(items, menu)).toEqual(["Drinks", "Foods", "Pastries"]);
});

test("uses saved categories first, then menu data, and ignores missing categories", () => {
  const menu = [
    { id: "drink-1", name: "Updated Name", category: "Beverages" },
  ] satisfies Pick<MenuItem, "id" | "name" | "category">[];
  const items = [
    { productId: "drink-1", name: "Old Order Name", qty: 1, price: 100, category: "Drinks" },
    { productId: "legacy", name: "Uncategorized", qty: 1, price: 50 },
  ] satisfies OrderItem[];

  expect(orderItemCategories(items, menu)).toEqual(["Drinks"]);
});

test("resolves the configured category by product id when an order has no category snapshot", () => {
  const menu = [
    { id: "coffee-1", name: "Spanish Latte", category: "Coffee" },
  ] satisfies Pick<MenuItem, "id" | "name" | "category">[];
  const orderItem = {
    productId: "coffee-1",
    name: "Spanish Latte",
    qty: 1,
    price: 150,
  } satisfies OrderItem;

  expect(orderItemCategory(orderItem, menu)).toBe("Coffee");
  expect(orderItemCategories([orderItem], menu)).toEqual(["Coffee"]);
});
