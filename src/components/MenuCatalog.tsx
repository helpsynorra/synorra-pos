"use client";

import { useMemo, useState, useTransition } from "react";
import {
  addMenuCategory,
  createMenuItem,
  deleteMenuCategory,
  deleteMenuItem,
  renameMenuCategory,
  setMenuItemAvailable,
  updateMenuItem,
} from "@/actions/menu";
import { addonIdFromName, DRINK_STYLES, drinkStyleLabel, drinkStyleLabelList, formatMoney, inferMenuCategoryType, isFoodOrPastry, menuCategoryTypeForName, menuCategoryTypeLabel, normalizeMenuAddons, normalizeMenuCategoryType, normalizeMenuStyles, normalizeMenuTypes, normalizeMenuTypeOptions } from "@/lib/menu";
import type { DrinkStyle, InventoryItem, MenuAddon, MenuCategoryType, MenuItem, MenuTypeOption } from "@/lib/types";

type MenuCatalogProps = {
  menu: MenuItem[];
  categories: string[];
  categoryTypes?: Record<string, MenuCategoryType>;
  inventory?: InventoryItem[];
};

type SubTab = "items" | "categories";

const field =
  "w-full rounded-xl border border-neutral-200 bg-white px-3.5 py-2.5 text-sm text-neutral-900 outline-none transition-all focus:border-neutral-900 focus:ring-1 focus:ring-neutral-900";

const iconBtn =
  "flex h-7 w-7 items-center justify-center rounded-lg text-neutral-400 transition-all hover:bg-neutral-100 hover:text-neutral-900 disabled:opacity-30";

const isSizeAddon = (addon: MenuAddon) => addon.id.startsWith("size:");

function PencilIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-3.5 w-3.5" fill="none" stroke="currentColor">
      <path d="M4 20h4l10.5-10.5a2.1 2.1 0 0 0-3-3L5 17v3Z" strokeWidth="1.7" strokeLinejoin="round" />
      <path d="M13.5 6.5l3 3" strokeWidth="1.7" />
    </svg>
  );
}

function TrashIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-3.5 w-3.5" fill="none" stroke="currentColor">
      <path d="M5 7h14M10 7V5h4v2M8 7l1 12h6l1-12" strokeWidth="1.7" />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-3.5 w-3.5" fill="none" stroke="currentColor">
      <path d="M5 12.5l4.5 4.5L19 7" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function CloseIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-3.5 w-3.5" fill="none" stroke="currentColor">
      <path d="M6 6l12 12M18 6L6 18" strokeWidth="1.8" strokeLinecap="round" />
    </svg>
  );
}

function EyeIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-3.5 w-3.5" fill="none" stroke="currentColor">
      <path d="M2.5 12s3.5-6.5 9.5-6.5S21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12Z" strokeWidth="1.7" />
      <circle cx="12" cy="12" r="2.5" strokeWidth="1.7" />
    </svg>
  );
}

function EyeOffIcon() {
  return (
    <svg viewBox="0 0 24 24" className="h-3.5 w-3.5" fill="none" stroke="currentColor">
      <path d="M3 3l18 18M10.5 10.7a2.5 2.5 0 0 0 3 3M7 7.4C4.6 8.8 3 12 3 12s3.5 6.5 9.5 6.5c1.4 0 2.7-.3 3.8-.8M16.8 16.2C19.2 14.8 21.5 12 21.5 12S18 5.5 12 5.5c-.7 0-1.3.1-1.9.2" strokeWidth="1.7" strokeLinecap="round" />
    </svg>
  );
}

function actionError(result: unknown) {
  if (
    result &&
    typeof result === "object" &&
    "error" in result &&
    typeof result.error === "string" &&
    result.error
  ) {
    return result.error;
  }
  return null;
}

export function MenuCatalog({ menu, categories, categoryTypes = {}, inventory = [] }: MenuCatalogProps) {
  const [tab, setTab] = useState<SubTab>("items");
  const [notice, setNotice] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const [newCategory, setNewCategory] = useState("");
  const [newCategoryType, setNewCategoryType] = useState<MenuCategoryType>("");
  const [editingCategory, setEditingCategory] = useState<string | null>(null);
  const [categoryName, setCategoryName] = useState("");
  const [categoryTypeDrafts, setCategoryTypeDrafts] = useState<Record<string, string>>({});
  const [filter, setFilter] = useState("All");
  const [editingId, setEditingId] = useState<string | "new" | null>(null);
  const [itemName, setItemName] = useState("");
  const [itemPrice, setItemPrice] = useState("");
  const [itemCategory, setItemCategory] = useState("");
  const [itemAvailable, setItemAvailable] = useState(true);
  const [itemInventoryMode, setItemInventoryMode] = useState<"none" | "stock_only" | "stock_and_recipe">("none");
  const [itemStockInventoryItemId, setItemStockInventoryItemId] = useState("");
  const [itemStockUsageAmount, setItemStockUsageAmount] = useState("1");
  const [itemStyles, setItemStyles] = useState<DrinkStyle[]>([]);
  const [itemAddons, setItemAddons] = useState<MenuAddon[]>([]);
  const [itemTypes, setItemTypes] = useState<MenuTypeOption[]>([]);
  const [itemImage, setItemImage] = useState("");
  const [itemPhoto, setItemPhoto] = useState<File | null>(null);

  const counts = useMemo(() => {
    const map = new Map<string, number>();
    for (const item of menu) {
      const key = item.category.toLowerCase();
      map.set(key, (map.get(key) ?? 0) + 1);
    }
    return map;
  }, [menu]);

  const visibleItems = useMemo(() => {
    const needle = filter.toLowerCase();
    return menu
      .filter((item) => filter === "All" || item.category.toLowerCase() === needle)
      .sort((a, b) => a.category.localeCompare(b.category) || a.name.localeCompare(b.name));
  }, [menu, filter]);
  const categoryTypeOptions = useMemo(() => {
    const uniqueTypes = new Map<string, string>();
    for (const type of [
      ...Object.values(categoryTypes),
      ...menu.flatMap((item) => item.categoryType ? [item.categoryType] : []),
    ]) {
      const value = normalizeMenuCategoryType(type);
      if (value) uniqueTypes.set(value.toLowerCase(), value);
    }
    return [...uniqueTypes.values()].sort((a, b) => a.localeCompare(b));
  }, [categoryTypes, menu]);
  const itemCategoryIsFoodOrPastry = isFoodOrPastry(itemCategory, categoryTypeForName(itemCategory));

  function flash(message: string | null) {
    setNotice(message);
  }

  function categoryTypeForName(category: string) {
    const direct = categoryTypes[category] ?? categoryTypes[category.toLowerCase()];
    return menuCategoryTypeForName(category, direct);
  }

  function startCreateItem() {
    setEditingId("new");
    setItemName("");
    setItemPrice("");
    setItemCategory(filter !== "All" ? filter : categories[0] ?? "");
    setItemAvailable(true);
    setItemInventoryMode("none");
    setItemStockInventoryItemId("");
    setItemStockUsageAmount("1");
    setItemStyles([]);
    setItemAddons([]);
    setItemTypes([]);
    setItemImage("");
    setItemPhoto(null);
    setNotice(null);
    setTab("items");
  }

  function startEditItem(item: MenuItem) {
    setEditingId(item.id);
    setItemName(item.name);
    setItemPrice(String(item.price));
    setItemCategory(item.category);
    setItemAvailable(item.available !== false);
    setItemInventoryMode(
      item.inventoryMode === "stock_only" || item.inventoryMode === "stock_and_recipe"
        ? item.inventoryMode
        : "none",
    );
    setItemStockInventoryItemId(item.stockInventoryItemId ?? "");
    setItemStockUsageAmount(String(item.stockUsageAmount ?? 1));
    setItemStyles(normalizeMenuStyles(item));
    setItemAddons(normalizeMenuAddons(item));
    setItemTypes(normalizeMenuTypeOptions(item));
    setItemImage(item.image);
    setItemPhoto(null);
    setNotice(null);
    setTab("items");
  }

  function resetItemForm() {
    setEditingId(null);
  }

  function itemFormData() {
    const data = new FormData();
    if (editingId && editingId !== "new") data.set("id", editingId);
    data.set("name", itemName);
    const sizes = itemAddons.filter(isSizeAddon);
    const basePrice = sizes.length
      ? Math.min(...sizes.map((size) => Number(size.price) || 0))
      : Number(itemPrice) || 0;
    data.set("price", String(basePrice));
    data.set("category", itemCategory);
    data.set("available", itemAvailable ? "true" : "false");
    data.set("inventoryMode", itemInventoryMode);
    data.set("stockInventoryItemId", sizes.length ? "" : itemStockInventoryItemId);
    data.set("stockUsageAmount", sizes.length ? "" : itemStockUsageAmount);
    data.set("stylesField", "1");
    for (const style of itemStyles) data.append("styles", style);
    data.set("addons", JSON.stringify(itemAddons.filter((addon) => addon.name.trim())));
    data.set("types", JSON.stringify(itemTypes.filter((type) => type.name.trim())));
    if (itemPhoto) data.set("photo", itemPhoto);
    return data;
  }

  return (
    <div className="min-h-screen min-w-0 space-y-6 rounded-none border-0 border-neutral-300 bg-white p-3 sm:rounded-xl sm:border sm:p-6">
      <div className="flex gap-2 overflow-x-auto border-b border-neutral-400 pb-3">
        {(
          [
            { id: "items", label: "Items" },
            { id: "categories", label: "Categories" },
          ] as const
        ).map((entry) => (
          <button
            key={entry.id}
            type="button"
            onClick={() => setTab(entry.id)}
            className={`shrink-0 px-4 py-1.5 rounded text-xs font-bold transition shadow-sm uppercase ${
              tab === entry.id ? "bg-black text-white" : "bg-white text-neutral-700 hover:bg-neutral-100"
            }`}
          >
            {entry.label}
          </button>
        ))}
      </div>

      <div className="w-full space-y-5">
        <div className="flex items-center justify-between gap-3">
          <h1 className="text-xl font-semibold tracking-tight text-neutral-900">
            {tab === "categories" ? "Categories" : "Items"}
          </h1>
          {tab === "items" ? (
            <button
              type="button"
              onClick={startCreateItem}
              className="rounded-full bg-black px-4 py-2 text-sm font-medium text-white hover:bg-neutral-800"
            >
              Add item
            </button>
          ) : null}
        </div>

        {notice ? <p className="text-sm text-neutral-500">{notice}</p> : null}

        {tab === "categories" ? (
          <div className="space-y-5">
            <form
              className="grid grid-cols-1 gap-3 rounded-2xl border border-neutral-200 bg-white p-4 lg:grid-cols-[minmax(0,1fr)_13rem_auto] lg:items-end"
              onSubmit={(event) => {
                event.preventDefault();
                const nextType = newCategoryType.trim();
                if (!nextType) {
                  flash("Enter a category type.");
                  return;
                }
                startTransition(async () => {
                  const result = await addMenuCategory(newCategory, normalizeMenuCategoryType(nextType));
                  const error = actionError(result);
                  if (error) {
                    flash(error);
                    return;
                  }
                  setNewCategory("");
                  setNewCategoryType("");
                  flash("Category added.");
                });
              }}
            >
              <label className="min-w-0 w-full text-xs font-medium text-neutral-600">
                <span className="mb-1.5 block">New category</span>
                <input
                  required
                  value={newCategory}
                  onChange={(event) => setNewCategory(event.target.value)}
                  placeholder="e.g. Coffee"
                  className={field}
                />
              </label>
              <label className="min-w-0 w-full text-xs font-medium text-neutral-600">
                <span className="mb-1.5 block">Type</span>
                <input
                  required
                  value={newCategoryType}
                  onChange={(event) => setNewCategoryType(event.target.value)}
                  placeholder="e.g. Drinks, Foods"
                  className={field}
                />
              </label>
              <button
                type="submit"
                disabled={pending || !newCategory.trim()}
                className="w-full rounded-full bg-black px-4 py-2 text-sm font-medium text-white hover:bg-neutral-800 disabled:opacity-40 lg:w-auto"
              >
                {pending ? "Saving..." : "Add category"}
              </button>
            </form>

            <div className="overflow-x-auto rounded-2xl border border-neutral-200 bg-white">
              <table className="w-full min-w-[480px] text-left text-sm">
                <thead>
                  <tr className="border-b border-neutral-200 text-xs font-medium tracking-wide text-neutral-400 uppercase">
                    <th className="px-4 py-3">Category</th>
                    <th className="px-4 py-3">Type</th>
                    <th className="px-4 py-3 text-right">Items</th>
                    <th className="sticky right-0 bg-white px-3 py-3 text-right"> </th>
                  </tr>
                </thead>
                <tbody>
                  {categories.length === 0 ? (
                    <tr>
                      <td colSpan={4} className="px-4 py-10 text-center text-sm text-neutral-400">
                        No categories yet.
                      </td>
                    </tr>
                  ) : (
                    categories.map((category) => {
                      const count = counts.get(category.toLowerCase()) ?? 0;
                      const editing = editingCategory === category;
                      const currentType = categoryTypeForName(category);
                      const typeDraft = categoryTypeDrafts[category] ?? currentType;
                      return (
                        <tr key={category} className="border-t border-neutral-100">
                          <td className="px-4 py-3">
                            {editing ? (
                              <input
                                value={categoryName}
                                onChange={(event) => setCategoryName(event.target.value)}
                                className={field}
                                autoFocus
                              />
                            ) : (
                              <span className="font-medium">{category}</span>
                            )}
                          </td>
                          <td className="px-4 py-3 text-neutral-500">
                            {editing ? (
                              <select
                                aria-label={`Type for ${category}`}
                                value={typeDraft}
                                disabled={pending}
                                onChange={(event) => {
                                  setCategoryTypeDrafts((drafts) => ({
                                    ...drafts,
                                    [category]: event.target.value,
                                  }));
                                }}
                                className={field}
                              >
                                {[...new Set([...categoryTypeOptions, typeDraft])].map((type) => (
                                  <option key={type} value={type}>
                                    {menuCategoryTypeLabel(type)}
                                  </option>
                                ))}
                              </select>
                            ) : (
                              <span>{menuCategoryTypeLabel(currentType)}</span>
                            )}
                          </td>
                          <td className="px-4 py-3 text-right text-neutral-500">{count}</td>
                          <td className="sticky right-0 bg-white px-3 py-3">
                            <div className="flex justify-end gap-0.5">
                              {editing ? (
                                <>
                                  <button
                                    type="button"
                                    aria-label={`Save ${category}`}
                                    disabled={pending}
                                    onClick={() =>
                                      startTransition(async () => {
                                        const nextType = typeDraft.trim();
                                        if (!nextType) {
                                          flash("Enter a category type.");
                                          return;
                                        }
                                        const result = await renameMenuCategory(
                                          category,
                                          categoryName,
                                          normalizeMenuCategoryType(nextType),
                                        );
                                        const error = actionError(result);
                                        if (error) {
                                          flash(error);
                                          return;
                                        }
                                        setEditingCategory(null);
                                        setCategoryTypeDrafts((drafts) => {
                                          const next = { ...drafts };
                                          delete next[category];
                                          return next;
                                        });
                                        if (filter === category) setFilter(categoryName.trim() || category);
                                        flash(
                                          categoryName.trim().toLowerCase() === category.toLowerCase()
                                            ? "Category updated."
                                            : "Category renamed.",
                                        );
                                      })
                                    }
                                    className={iconBtn}
                                  >
                                    <CheckIcon />
                                  </button>
                                  <button
                                    type="button"
                                    aria-label="Cancel rename"
                                    onClick={() => {
                                      setEditingCategory(null);
                                      setCategoryTypeDrafts((drafts) => {
                                        const next = { ...drafts };
                                        delete next[category];
                                        return next;
                                      });
                                    }}
                                    className={iconBtn}
                                  >
                                    <CloseIcon />
                                  </button>
                                </>
                              ) : (
                                <>
                                  <button
                                    type="button"
                                    aria-label={`Rename ${category}`}
                                    onClick={() => {
                                      setEditingCategory(category);
                                      setCategoryName(category);
                                      setCategoryTypeDrafts((drafts) => ({
                                        ...drafts,
                                        [category]: currentType,
                                      }));
                                      setNotice(null);
                                    }}
                                    className={iconBtn}
                                  >
                                    <PencilIcon />
                                  </button>
                                  <button
                                    type="button"
                                    aria-label={`Delete ${category}`}
                                    disabled={pending}
                                    onClick={() => {
                                      if (count > 0) {
                                        flash("Move or delete items in this category first.");
                                        return;
                                      }
                                      startTransition(async () => {
                                        const result = await deleteMenuCategory(category);
                                        const error = actionError(result);
                                        if (error) {
                                          flash(error);
                                          return;
                                        }
                                        if (filter === category) setFilter("All");
                                        flash("Category deleted.");
                                      });
                                    }}
                                    className={`${iconBtn} hover:bg-red-50 hover:text-red-600`}
                                  >
                                    <TrashIcon />
                                  </button>
                                </>
                              )}
                            </div>
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>
          </div>
        ) : (
          <>
            <div className="flex flex-wrap items-center gap-2">
              {["All", ...categories].map((name) => (
                <button
                  key={name}
                  type="button"
                  onClick={() => setFilter(name)}
                  className={`rounded-full px-3 py-1.5 text-xs font-medium ${
                    filter === name
                      ? "bg-black text-white"
                      : "bg-white text-neutral-600 ring-1 ring-neutral-200 hover:text-black"
                  }`}
                >
                  {name}
                </button>
              ))}
            </div>

            {editingId ? (
              <form
                className="mx-auto max-w-7xl space-y-5 rounded-2xl border border-neutral-200 bg-white p-4 sm:p-6"
                onSubmit={(event) => {
                  event.preventDefault();
                  if (itemAddons.some((addon) => isSizeAddon(addon) && !addon.name.trim())) {
                    flash("Enter a name for every size before saving.");
                    return;
                  }
                  const sizes = itemAddons.filter(isSizeAddon);
                  if (sizes.some((size) => !Number.isFinite(Number(size.price)) || Number(size.price) <= 0)) {
                    flash("Enter a valid price for every size.");
                    return;
                  }
                  startTransition(async () => {
                    const result =
                      editingId === "new" ? await createMenuItem(itemFormData()) : await updateMenuItem(itemFormData());
                    const error = actionError(result);
                    if (error) {
                      flash(error);
                      return;
                    }
                    resetItemForm();
                    flash(editingId === "new" ? "Item added." : "Item updated.");
                  });
                }}
              >
                <div className="flex items-center justify-between border-b border-neutral-200 pb-3">
                  <div>
                    <p className="text-lg font-semibold text-neutral-900">{editingId === "new" ? "Add menu item" : "Edit menu item"}</p>
                    <p className="mt-0.5 text-xs text-neutral-500">Fill in the sections below, then save your changes.</p>
                  </div>
                  <button type="button" onClick={resetItemForm} className="text-xs text-neutral-500 hover:text-black">
                    Cancel
                  </button>
                </div>
                <section className="space-y-4 rounded-xl border border-neutral-200 bg-neutral-50/60 p-4 sm:p-5">
                <div>
                  <h3 className="text-sm font-semibold text-neutral-900">Item details</h3>
                  <p className="mt-1 text-xs text-neutral-500">Set the name, category, photo, and serving style.</p>
                </div>
                <div className={`grid gap-3 ${itemAddons.some(isSizeAddon) ? "sm:grid-cols-2" : "sm:grid-cols-3"}`}>
                  <label className="text-xs font-medium text-neutral-600">
                    <span className="mb-1.5 block">Name</span>
                    <input value={itemName} onChange={(event) => setItemName(event.target.value)} className={field} required />
                  </label>
                  {!itemAddons.some(isSizeAddon) ? (
                    <label className="text-xs font-medium text-neutral-600">
                      <span className="mb-1.5 block">Base price</span>
                      <input
                        type="number"
                        min="0"
                        step="1"
                        value={itemPrice}
                        onChange={(event) => setItemPrice(event.target.value)}
                        className={field}
                        required
                      />
                    </label>
                  ) : null}
                  <label className="text-xs font-medium text-neutral-600">
                    <span className="mb-1.5 block">Category</span>
                    <select
                      value={itemCategory}
                      onChange={(event) => {
                        const next = event.target.value;
                        setItemCategory(next);
                        if (isFoodOrPastry(next, categoryTypeForName(next))) setItemStyles([]);
                      }}
                      className={field}
                      required
                    >
                      <option value="" disabled>
                        Select a category
                      </option>
                      {categories.map((category) => (
                        <option key={category} value={category}>
                          {category}
                        </option>
                      ))}
                    </select>
                  </label>
                </div>
                <div className="flex items-center gap-3">
                  {itemImage ? <img src={itemImage} alt="Menu item preview" className="h-16 w-16 rounded-xl object-cover" /> : null}
                  <label className="text-xs font-medium text-neutral-600">
                    <span className="mb-1.5 block">Menu photo</span>
                    <input type="file" accept="image/jpeg,image/png,image/webp,image/gif" onChange={(event) => {
                      const file = event.target.files?.[0] ?? null;
                      setItemPhoto(file);
                      if (file) setItemImage(URL.createObjectURL(file));
                    }} className="block max-w-full text-xs" />
                  </label>
                </div>
                {!itemCategoryIsFoodOrPastry ? (
                  <div>
                    <p className="mb-1.5 text-xs font-medium text-neutral-600">Type</p>
                    <div className="flex gap-2">
                      {DRINK_STYLES.map((style) => {
                        const on = itemStyles.includes(style);
                        return (
                          <button
                            key={style}
                            type="button"
                            onClick={() =>
                              setItemStyles((current) =>
                                on ? current.filter((entry) => entry !== style) : [...current, style],
                              )
                            }
                            className={`rounded-full border px-3 py-1.5 text-xs font-medium ${
                              on ? "border-black bg-black text-white" : "border-neutral-200 bg-white text-neutral-600"
                            }`}
                          >
                            {drinkStyleLabel(style)}
                          </button>
                        );
                      })}
                    </div>
                  </div>
                ) : null}
                </section>
                <section className="space-y-3 rounded-xl border border-neutral-200 bg-neutral-50/60 p-4 sm:p-5">
                <div>
                  <div className="mb-1.5 flex items-center justify-between gap-2">
                    <div>
                      <h3 className="text-sm font-semibold text-neutral-900">Sizes and prices</h3>
                      <p className="mt-1 text-xs text-neutral-500">Add each size with its full selling price.</p>
                    </div>
                    <button
                      type="button"
                      onClick={() =>
                        setItemAddons((current) => [
                          ...current,
                          {
                            id: `size:${addonIdFromName("size", Date.now())}`,
                            name: "",
                            price: 0,
                          },
                        ])
                      }
                      className="rounded-lg border border-neutral-300 bg-white px-3 py-2 text-xs font-medium text-neutral-700 hover:border-neutral-500 hover:text-black"
                    >
                      + Add size
                    </button>
                  </div>
                  <p className="mb-3 text-xs text-neutral-500">
                    {itemInventoryMode === "stock_only"
                      ? "You can link each size to its own stock item below."
                      : "For example, 16 oz and 22 oz can have different prices."}
                  </p>
                  {itemAddons.some(isSizeAddon) ? (
                    <div className={`mb-2 hidden gap-2 px-1 text-[11px] font-medium text-neutral-500 sm:grid ${itemInventoryMode === "stock_only" ? "sm:grid-cols-[minmax(150px,1fr)_110px_minmax(180px,1fr)_110px_auto]" : "sm:grid-cols-[minmax(0,1fr)_180px_auto]"}`}>
                      <span>Size</span><span>Full price</span>{itemInventoryMode === "stock_only" ? <><span>Stock item</span><span>Used per sale</span></> : null}<span />
                    </div>
                  ) : null}
                  {itemAddons.filter(isSizeAddon).length === 0 ? (
                    <p className="rounded-lg border border-dashed border-neutral-300 bg-white px-3 py-4 text-center text-xs text-neutral-500">No sizes added. Use the base price above for a single price.</p>
                  ) : itemAddons.filter(isSizeAddon).map((size) => {
                    const index = itemAddons.findIndex((entry) => entry.id === size.id);
                    const sizeStock = inventory.find((stock) => stock.id === size.inventoryItemId);
                    return (
                      <div key={size.id} className={`mb-2 grid grid-cols-1 gap-2 ${itemInventoryMode === "stock_only" ? "sm:grid-cols-[minmax(150px,1fr)_110px_minmax(180px,1fr)_110px_auto]" : "sm:grid-cols-[1fr_180px_auto]"}`}>
                        <input
                          value={size.name}
                          onChange={(event) =>
                            setItemAddons((current) => current.map((entry) =>
                              entry.id === size.id ? { ...entry, name: event.target.value } : entry,
                            ))
                          }
                          placeholder="e.g. 16 oz"
                          aria-label="Size name"
                          className={field}
                        />
                        <input
                          type="number"
                          min="0"
                          step="1"
                          value={String(size.price)}
                          onChange={(event) => {
                            const fullPrice = Number(event.target.value);
                            if (!Number.isFinite(fullPrice) || fullPrice < 0) return;
                            setItemAddons((current) => current.map((entry) =>
                              entry.id === size.id ? { ...entry, price: fullPrice } : entry,
                            ));
                          }}
                          aria-label="Size price"
                          className={field}
                        />
                        {itemInventoryMode === "stock_only" ? (
                          <>
                            <select
                              value={size.inventoryItemId ?? ""}
                              onChange={(event) => {
                                const stock = inventory.find((entry) => entry.id === event.target.value);
                                setItemAddons((current) => current.map((entry) => entry.id === size.id
                                  ? { ...entry, inventoryItemId: stock?.id, usageUnit: stock?.unit, usageAmount: entry.usageAmount ?? 1 }
                                  : entry));
                              }}
                              className={field}
                              aria-label={`Stock item for ${size.name || "size"}`}
                            >
                              <option value="">Select stock item</option>
                              {inventory.map((stock) => <option key={stock.id} value={stock.id}>{stock.name}</option>)}
                            </select>
                            <label className="flex items-center gap-1 text-xs text-neutral-500">
                              <input
                                type="number"
                                min="0.001"
                                step="any"
                                value={size.usageAmount ?? 1}
                                onChange={(event) => {
                                  const usageAmount = Number(event.target.value);
                                  setItemAddons((current) => current.map((entry) => entry.id === size.id
                                    ? { ...entry, usageAmount: Number.isFinite(usageAmount) ? usageAmount : 0, usageUnit: sizeStock?.unit ?? entry.usageUnit }
                                    : entry));
                                }}
                                className={`${field} min-w-0`}
                                aria-label={`Stock used per ${size.name || "size"}`}
                              />
                              {sizeStock?.unit || size.usageUnit || "pcs"}
                            </label>
                          </>
                        ) : null}
                        <button
                          type="button"
                          aria-label={`Remove size ${size.name}`}
                          onClick={() => setItemAddons((current) => current.filter((entry) => entry.id !== size.id))}
                          className="text-xs text-neutral-400 hover:text-black"
                        >
                          Remove
                        </button>
                      </div>
                    );
                  })}
                </div>
                </section>
                <section className="space-y-3 rounded-xl border border-neutral-200 bg-neutral-50/60 p-4 sm:p-5">
                <div>
                  <div className="mb-1.5 flex items-center justify-between gap-2">
                    <div>
                      <h3 className="text-sm font-semibold text-neutral-900">Types</h3>
                      <p className="mt-1 text-xs text-neutral-500">Optional choices customers can select. Set an extra price only when needed.</p>
                    </div>
                    <button
                      type="button"
                      onClick={() => setItemTypes((current) => [...current, { name: "", price: 0 }])}
                      className="rounded-lg border border-neutral-300 bg-white px-3 py-2 text-xs font-medium text-neutral-700 hover:border-neutral-500 hover:text-black"
                    >
                      + Add type
                    </button>
                  </div>
                  {itemTypes.length === 0 ? (
                    <p className="rounded-lg border border-dashed border-neutral-300 bg-white px-3 py-4 text-center text-xs text-neutral-500">No types added.</p>
                  ) : (
                    <div className="space-y-2">
                      {itemTypes.map((type, index) => (
                        <div key={`type-${index}`} className="grid grid-cols-1 gap-2 sm:grid-cols-[minmax(0,1fr)_160px_auto]">
                          <input
                            value={type.name}
                            onChange={(event) =>
                              setItemTypes((current) =>
                                current.map((entry, entryIndex) =>
                                  entryIndex === index ? { ...entry, name: event.target.value } : entry,
                                ),
                              )
                            }
                            placeholder="e.g. Cheese"
                            className={`${field} flex-1`}
                          />
                          <input
                            type="number"
                            min="0"
                            step="1"
                            value={type.price || ""}
                            onChange={(event) =>
                              setItemTypes((current) => current.map((entry, entryIndex) =>
                                entryIndex === index
                                  ? { ...entry, price: Math.max(0, Number(event.target.value) || 0) }
                                  : entry,
                              ))
                            }
                            placeholder="Extra price"
                            aria-label={`Optional extra price for ${type.name || `type ${index + 1}`}`}
                            className={`${field} w-48`}
                          />
                          <button
                            type="button"
                            aria-label="Remove type"
                            onClick={() =>
                              setItemTypes((current) => current.filter((_, entryIndex) => entryIndex !== index))
                            }
                            className="text-xs text-neutral-400 hover:text-black"
                          >
                            Remove
                          </button>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
                </section>
                <section className="space-y-3 rounded-xl border border-neutral-200 bg-neutral-50/60 p-4 sm:p-5">
                <div>
                  <div className="mb-1.5 flex items-center justify-between gap-2">
                    <div>
                      <h3 className="text-sm font-semibold text-neutral-900">Add-ons</h3>
                      <p className="mt-1 text-xs text-neutral-500">Optional extras with their own price and optional stock deduction.</p>
                    </div>
                    <button
                      type="button"
                      onClick={() =>
                        setItemAddons((current) => [
                          ...current,
                          {
                            id: addonIdFromName("addon", current.length),
                            name: "",
                            price: 0,
                            qtyEnabled: false,
                          },
                        ])
                      }
                      className="rounded-lg border border-neutral-300 bg-white px-3 py-2 text-xs font-medium text-neutral-700 hover:border-neutral-500 hover:text-black"
                    >
                      + Add add-on
                    </button>
                  </div>
                  {itemAddons.filter((addon) => !isSizeAddon(addon)).length === 0 ? (
                    <p className="text-xs text-neutral-400">
                      e.g. Oat milk ₱30, Extra espresso ₱40.
                    </p>
                  ) : (
                    <div className="space-y-2">
                      <div className="hidden grid-cols-[1fr_88px_1fr_88px_auto] gap-2 text-[11px] text-neutral-400 lg:grid">
                        <span>Name</span>
                        <span>Extra ₱</span>
                        <span>Deduct from</span>
                        <span>Amount</span>
                        <span />
                      </div>
                      {itemAddons.filter((addon) => !isSizeAddon(addon)).map((addon) => {
                        const index = itemAddons.findIndex((entry) => entry.id === addon.id);
                        const stock = inventory.find((item) => item.id === addon.inventoryItemId);
                        return (
                          <div
                            key={addon.id}
                            className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-[1fr_88px_1fr_88px_auto] lg:items-center"
                          >
                            <input
                              value={addon.name}
                              onChange={(event) =>
                                setItemAddons((current) =>
                                  current.map((entry, entryIndex) =>
                                    entryIndex === index ? { ...entry, name: event.target.value } : entry,
                                  ),
                                )
                              }
                              placeholder="Oat milk"
                              className={field}
                            />
                            <input
                                  inputMode="numeric"
                                  value={addon.price === 0 ? "" : String(addon.price)}
                                  onChange={(event) => {
                                    const raw = event.target.value.replace(/[^\d]/g, "");
                                    setItemAddons((current) =>
                                      current.map((entry, entryIndex) =>
                                        entryIndex === index
                                          ? { ...entry, price: raw ? Math.max(0, Number(raw)) : 0 }
                                          : entry,
                                      ),
                                    );
                                  }}
                                  className={field}
                                  aria-label="Add-on extra price"
                                  placeholder="20"
                                />
                                <select
                                  value={addon.inventoryItemId ?? ""}
                                  onChange={(event) => {
                                    const nextId = event.target.value;
                                    const nextStock = inventory.find((item) => item.id === nextId);
                                    setItemAddons((current) =>
                                      current.map((entry, entryIndex) =>
                                        entryIndex === index
                                          ? {
                                              ...entry,
                                              inventoryItemId: nextId || undefined,
                                              usageUnit: nextStock?.unit || entry.usageUnit,
                                            }
                                          : entry,
                                      ),
                                    );
                                  }}
                                  className={field}
                                  aria-label="Stock item to deduct"
                                >
                                  <option value="">No stock deduction</option>
                                  {inventory.map((item) => (
                                    <option key={item.id} value={item.id}>
                                      {item.name}
                                    </option>
                                  ))}
                                </select>
                            <div className="flex items-center gap-1">
                              <input
                                    inputMode="decimal"
                                    value={addon.usageAmount ? String(addon.usageAmount) : ""}
                                    onChange={(event) => {
                                      const raw = event.target.value.replace(/[^\d.]/g, "");
                                      const usageAmount = raw ? Math.max(0, Number(raw)) : 0;
                                      setItemAddons((current) =>
                                        current.map((entry, entryIndex) =>
                                          entryIndex === index
                                            ? { ...entry, usageAmount: usageAmount || undefined }
                                            : entry,
                                        ),
                                      );
                                    }}
                                    className={field}
                                    aria-label="Add-on usage amount"
                                    placeholder="20"
                              />
                              <span className="shrink-0 text-[11px] text-neutral-400">
                                {stock?.unit || addon.usageUnit || "ml"}
                              </span>
                            </div>
                            <button
                              type="button"
                              aria-label="Remove add-on"
                              onClick={() =>
                                setItemAddons((current) =>
                                  current.filter((_, entryIndex) => entryIndex !== index),
                                )
                              }
                              className="text-xs text-neutral-400 hover:text-black"
                            >
                              Remove
                            </button>
                          </div>
                        );
                      })}
                    </div>
                  )}
                </div>
                </section>
                <section className="space-y-4 rounded-xl border border-neutral-200 bg-neutral-50/60 p-4 sm:p-5">
                  <div>
                    <h3 className="text-sm font-semibold text-neutral-900">Inventory and availability</h3>
                    <p className="mt-1 text-xs text-neutral-500">Choose one method if this item should use inventory. Leave both unchecked for no automatic deductions.</p>
                  </div>
                  <label className="flex items-center gap-2 rounded-lg bg-white px-3 py-2 text-sm text-neutral-700">
                    <input
                      type="checkbox"
                      checked={itemAvailable}
                      onChange={(event) => setItemAvailable(event.target.checked)}
                      className="h-4 w-4 accent-black"
                    />
                    Available for sale in POS
                  </label>
                  <div className="grid gap-2 sm:grid-cols-2" role="group" aria-label="Inventory tracking mode">
                    <label className={`flex cursor-pointer items-start gap-3 rounded-xl border p-3 transition ${itemInventoryMode === "stock_only" ? "border-neutral-900 bg-white" : "border-neutral-200 bg-white hover:border-neutral-400"}`}>
                      <input type="checkbox" checked={itemInventoryMode === "stock_only"} onChange={() => setItemInventoryMode((current) => current === "stock_only" ? "none" : "stock_only")} className="mt-0.5 h-4 w-4 accent-black" />
                      <span><span className="block text-sm font-medium text-neutral-800">Stock only</span><span className="mt-0.5 block text-xs text-neutral-500">Deduct the selected stock item for each sale.</span></span>
                    </label>
                    <label className={`flex cursor-pointer items-start gap-3 rounded-xl border p-3 transition ${itemInventoryMode === "stock_and_recipe" ? "border-neutral-900 bg-white" : "border-neutral-200 bg-white hover:border-neutral-400"}`}>
                      <input type="checkbox" checked={itemInventoryMode === "stock_and_recipe"} onChange={() => setItemInventoryMode((current) => current === "stock_and_recipe" ? "none" : "stock_and_recipe")} className="mt-0.5 h-4 w-4 accent-black" />
                      <span><span className="block text-sm font-medium text-neutral-800">Stock and recipe</span><span className="mt-0.5 block text-xs text-neutral-500">Deduct recipe ingredients when a recipe is configured.</span></span>
                    </label>
                  </div>
                {itemInventoryMode === "stock_only" && !itemAddons.some(isSizeAddon) ? (
                  <div className="grid gap-3 rounded-xl border border-neutral-200 bg-white p-3 sm:grid-cols-[minmax(0,1fr)_160px]">
                    <label className="text-xs font-medium text-neutral-600">
                      Stock item
                      <select
                        value={itemStockInventoryItemId}
                        onChange={(event) => setItemStockInventoryItemId(event.target.value)}
                        className={`${field} mt-1`}
                        aria-label="Stock item for this menu product"
                      >
                        <option value="">Select stock item</option>
                        {inventory.map((stock) => (
                          <option key={stock.id} value={stock.id}>{stock.name}</option>
                        ))}
                      </select>
                    </label>
                    <label className="text-xs font-medium text-neutral-600">
                      Used per sale ({inventory.find((stock) => stock.id === itemStockInventoryItemId)?.unit || "pcs"})
                      <input
                        type="number"
                        min="0.001"
                        step="any"
                        value={itemStockUsageAmount}
                        onChange={(event) => setItemStockUsageAmount(event.target.value)}
                        className={`${field} mt-1`}
                        aria-label="Stock used per sale"
                      />
                    </label>
                  </div>
                ) : null}
                </section>
                <div className="flex justify-end border-t border-neutral-200 pt-4">
                  <button
                    type="submit"
                    disabled={pending || !itemName.trim() || !itemCategory || categories.length === 0}
                    className="rounded-full bg-black px-4 py-2 text-sm font-medium text-white hover:bg-neutral-800 disabled:opacity-40"
                  >
                    {pending ? "Saving..." : editingId === "new" ? "Add" : "Save"}
                  </button>
                </div>
              </form>
            ) : null}

            <div className="overflow-x-auto rounded-2xl border border-neutral-200 bg-white">
              <table className="w-full min-w-[560px] text-left text-sm">
                <thead>
                  <tr className="border-b border-neutral-200 text-xs font-medium tracking-wide text-neutral-400 uppercase">
                    <th className="px-4 py-3">Item</th>
                    <th className="px-4 py-3">Category</th>
                    <th className="px-4 py-3">Type</th>
                    <th className="px-4 py-3 text-right">Price</th>
                    <th className="px-4 py-3">Status</th>
                    <th className="sticky right-0 bg-white px-3 py-3 text-right"> </th>
                  </tr>
                </thead>
                <tbody>
                  {visibleItems.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="px-4 py-10 text-center text-sm text-neutral-400">
                        {categories.length === 0 ? "Add a category, then add items." : "No items in this category."}
                      </td>
                    </tr>
                  ) : (
                    visibleItems.map((item) => (
                      <tr key={item.id} className="border-t border-neutral-100">
                        <td className="px-4 py-3 font-medium">
                          <p>{item.name}</p>
                          {normalizeMenuAddons(item).some((addon) => !isSizeAddon(addon)) ? (
                            <p className="mt-0.5 text-[11px] text-neutral-400">
                              {normalizeMenuAddons(item).filter((addon) => !isSizeAddon(addon))
                                .map((addon) => {
                                  const stock = inventory.find((entry) => entry.id === addon.inventoryItemId);
                                  const extra = addon.price > 0 ? ` +₱${addon.price}` : "";
                                  const used =
                                    addon.usageAmount && stock
                                      ? ` · ${addon.usageAmount}${stock.unit || addon.usageUnit || ""} ${stock.name}`
                                      : "";
                                  return `${addon.name}${extra}${used}`;
                                })
                                .join(", ")}
                            </p>
                          ) : null}
                          {normalizeMenuAddons(item).some(isSizeAddon) ? (
                            <p className="mt-0.5 text-[11px] text-neutral-400">
                              Sizes: {normalizeMenuAddons(item).filter(isSizeAddon).map((size) => `${size.name} ₱${size.price}`).join(" · ")}
                            </p>
                          ) : null}
                          {normalizeMenuTypes(item).length > 0 ? (
                            <p className="mt-0.5 text-[11px] text-neutral-400">
                              Types: {normalizeMenuTypes(item).join(", ")}
                            </p>
                          ) : null}
                        </td>
                        <td className="px-4 py-3 text-neutral-500">{item.category}</td>
                        <td className="px-4 py-3 text-neutral-500">{drinkStyleLabelList(item)}</td>
                        <td className="px-4 py-3 text-right">{formatMoney(item.price)}</td>
                        <td className="px-4 py-3">
                          <span className={`text-xs ${item.available !== false ? "text-neutral-900" : "text-neutral-400"}`}>
                            {item.available !== false ? "On" : "Hidden"}
                          </span>
                        </td>
                        <td className="sticky right-0 bg-white px-3 py-3">
                          <div className="flex justify-end gap-0.5">
                            <button
                              type="button"
                              aria-label={item.available === false ? `Show ${item.name}` : `Hide ${item.name}`}
                              disabled={pending}
                              onClick={() =>
                                startTransition(async () => {
                                  await setMenuItemAvailable(item.id, item.available === false);
                                })
                              }
                              className={iconBtn}
                            >
                              {item.available === false ? <EyeIcon /> : <EyeOffIcon />}
                            </button>
                            <button
                              type="button"
                              aria-label={`Edit ${item.name}`}
                              onClick={() => startEditItem(item)}
                              className={iconBtn}
                            >
                              <PencilIcon />
                            </button>
                            <button
                              type="button"
                              aria-label={`Delete ${item.name}`}
                              disabled={pending}
                              onClick={() => {
                                startTransition(async () => {
                                  const result = await deleteMenuItem(item.id);
                                  const error = actionError(result);
                                  if (error) {
                                    flash(error);
                                    return;
                                  }
                                  if (editingId === item.id) resetItemForm();
                                  flash("Item deleted.");
                                });
                              }}
                              className={`${iconBtn} hover:bg-red-50 hover:text-red-600`}
                            >
                              <TrashIcon />
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
