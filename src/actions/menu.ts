"use server";

import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { addonIdFromName, DRINK_STYLES, isFoodOrPastry, menuItemId, normalizeMenuAddons, normalizeMenuCategoryType, normalizeMenuStyles, stripMenuImage } from "@/lib/menu";
import type { DrinkStyle, MenuAddon, MenuCategoryType, MenuItem } from "@/lib/types";
import {
  deleteMenuCategoryRecord,
  deleteMenuItemRecord,
  getFreshStore,
  getStore,
  insertMenuCategoryRecord,
  renameMenuCategoryAtomic,
  setMenuItemAvailableRecord,
  upsertMenuItemRecord,
  uploadPublicMenuPhoto,
} from "@/lib/store";

const PHOTO_TYPES: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/gif": "gif",
};
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;

async function requireMenuEditor() {
  const session = await getSession();
  if (!session || (session.role !== "admin" && session.role !== "cashier")) {
    throw new Error("Only an Owner or admin can edit the menu.");
  }
  return session;
}

function refresh() {
  revalidatePath("/pos");
  revalidatePath("/owner");
  revalidatePath("/drinks");
  revalidatePath("/");
}

function isSafeImage(src: string) {
  // Strip legacy "#cc-opt=" option markers (written by another branch) before
  // validating the path so existing rows still pass.
  const path = stripMenuImage(src);
  return (
    path.startsWith("/images/") ||
    path.startsWith("/uploads/menu/") ||
    path.includes(".supabase.co/storage/")
  );
}

function readText(formData: FormData, key: string) {
  return String(formData.get(key) ?? "").trim();
}

async function saveMenuPhoto(file: File, id: string) {
  const ext = PHOTO_TYPES[file.type];
  if (!ext) {
    return { error: "Use a JPG, PNG, WEBP, or GIF photo." };
  }
  if (file.size > MAX_PHOTO_BYTES) {
    return { error: "Keep photos under 5MB." };
  }

  const safeId = id.replace(/[^a-z0-9-]/gi, "") || "item";
  const filename = `${safeId}-${Date.now().toString(36)}.${ext}`;
  const bytes = Buffer.from(await file.arrayBuffer());

  try {
    const src = await uploadPublicMenuPhoto(filename, bytes, file.type);
    return { src };
  } catch (error) {
    return {
      error: error instanceof Error ? error.message : "Could not upload photo.",
    };
  }
}

function photoFromForm(formData: FormData) {
  const photo = formData.get("photo");
  return photo instanceof File && photo.size > 0 ? photo : null;
}

function stylesFromForm(
  formData: FormData,
  category: string,
  categoryType: MenuCategoryType,
  existing?: MenuItem,
): DrinkStyle[] {
  if (isFoodOrPastry(category, categoryType)) return [];
  const selected: DrinkStyle[] = formData.getAll("styles").flatMap((value) => {
    const style = String(value);
    return style === "iced" || style === "hot" ? [style] : [];
  });
  // The current form always sends stylesField=1, so "no styles keys" means
  // the admin deliberately selected none - persist the empty selection.
  // Without the marker (an older build), fall back to the previous semantics:
  // keep the item's existing styles on edit, or default to both on create.
  if (formData.get("stylesField") === "1") return selected;
  if (selected.length > 0) return normalizeMenuStyles({ category, styles: selected });
  return normalizeMenuStyles({ category, styles: existing?.styles ?? DRINK_STYLES });
}

function addonsFromForm(formData: FormData): MenuAddon[] {
  const packed = formData.get("addons");
  if (typeof packed === "string" && packed.trim()) {
    try {
      const parsed = JSON.parse(packed) as MenuAddon[];
      if (Array.isArray(parsed)) return normalizeMenuAddons({ addons: parsed });
    } catch {
      // Fall through to the field list below.
    }
  }
  const names = formData.getAll("addonName").map((value) => String(value ?? "").trim());
  const prices = formData.getAll("addonPrice").map((value) => String(value ?? "").trim());
  const ids = formData.getAll("addonId").map((value) => String(value ?? "").trim());
  const qtyFlags = formData.getAll("addonQtyEnabled").map((value) => String(value ?? "").trim());
  return normalizeMenuAddons({
    addons: names.flatMap((name, index) => {
      if (!name) return [];
      const price = Number(prices[index]);
      return [
        {
          id: ids[index] || addonIdFromName(name, index),
          name,
          price: Number.isFinite(price) ? price : 0,
          qtyEnabled: qtyFlags[index] === "1",
        },
      ];
    }),
  });
}

function typesFromForm(formData: FormData): string[] {
  const packed = formData.get("types");
  if (typeof packed !== "string" || !packed.trim()) return [];
  try {
    const parsed: unknown = JSON.parse(packed);
    if (!Array.isArray(parsed)) return [];
    return [...new Set(parsed
      .filter((value): value is string => typeof value === "string")
      .map((value) => value.trim())
      .filter(Boolean))];
  } catch {
    return [];
  }
}

export async function addMenuCategory(name: string, type?: MenuCategoryType) {
  await requireMenuEditor();
  const category = name.trim();
  if (!category) {
    return { error: "Enter a category name." };
  }

  const categoryType = normalizeMenuCategoryType(type ?? "drink");
  const result = await insertMenuCategoryRecord(category, categoryType);
  if (!result.ok) return { error: result.error };
  refresh();
  return { ok: true };
}

export async function renameMenuCategory(from: string, to: string, type?: MenuCategoryType) {
  await requireMenuEditor();
  const prev = from.trim();
  const next = to.trim();
  if (!prev) return { error: "Category not found." };
  if (!next) return { error: "Enter a category name." };

  const store = await getStore();
  const taken = store.categories.some(
    (entry) => entry.toLowerCase() === next.toLowerCase() && entry.toLowerCase() !== prev.toLowerCase(),
  );
  if (taken) {
    return { error: "That category is already on the board." };
  }

  const categoryType = normalizeMenuCategoryType(type ?? "drink");
  const result = await renameMenuCategoryAtomic(prev, next, categoryType);
  if (!result.ok) return { error: result.error };

  refresh();
  return { ok: true };
}

export async function deleteMenuCategory(name: string) {
  await requireMenuEditor();
  const category = name.trim();
  if (!category) return { error: "Category not found." };

  const store = await getStore();
  const inUse = store.menu.some(
    (item) => item.category.toLowerCase() === category.toLowerCase(),
  );
  if (inUse) {
    return { error: "Move or delete drinks in this category first." };
  }

  try {
    await deleteMenuCategoryRecord(category);
  } catch (error) {
    return { error: error instanceof Error ? error.message : "Could not delete that category." };
  }
  refresh();
  return { ok: true };
}

export async function createMenuItem(formData: FormData) {
  await requireMenuEditor();
  const name = readText(formData, "name");
  const category = readText(formData, "category");
  const addons = addonsFromForm(formData);
  const sizes = addons.filter((addon) => addon.id.startsWith("size:"));
  const price = sizes.length
    ? Math.min(...sizes.map((size) => Number(size.price)))
    : Number(readText(formData, "price"));
  const available = readText(formData, "available") !== "false";
  const photo = photoFromForm(formData);

  if (!name || !category) {
    return { error: "Name and category are required." };
  }
  if (!Number.isFinite(price) || price <= 0) {
    return { error: sizes.length ? "Enter a valid price for every size." : "Enter a valid price." };
  }
  const store = await getStore();
  const categoryType = normalizeMenuCategoryType(
    store.categoryTypes?.[category] ??
      Object.entries(store.categoryTypes ?? {}).find(([name]) => name.toLowerCase() === category.toLowerCase())?.[1] ??
      "other",
  );

  const id = menuItemId(name);
  let image = "/images/logo.png";
  if (photo) {
    const saved = await saveMenuPhoto(photo, id);
    if ("error" in saved && saved.error) return { error: saved.error };
    if ("src" in saved && saved.src) image = saved.src;
  }

  await upsertMenuItemRecord({
    id,
    name,
    price: Math.round(price),
    category,
    categoryType,
    image,
    available,
    styles: stylesFromForm(formData, category, categoryType),
    addons,
    types: typesFromForm(formData),
  });
  refresh();
  return { ok: true };
}

export async function updateMenuItem(formData: FormData) {
  await requireMenuEditor();
  const id = readText(formData, "id");
  const name = readText(formData, "name");
  const category = readText(formData, "category");
  const addons = addonsFromForm(formData);
  const sizes = addons.filter((addon) => addon.id.startsWith("size:"));
  const price = sizes.length
    ? Math.min(...sizes.map((size) => Number(size.price)))
    : Number(readText(formData, "price"));
  const available = readText(formData, "available") !== "false";
  const photo = photoFromForm(formData);

  if (!id) return { error: "Item not found." };
  if (!name || !category) {
    return { error: "Name and category are required." };
  }
  if (!Number.isFinite(price) || price <= 0) {
    return { error: sizes.length ? "Enter a valid price for every size." : "Enter a valid price." };
  }

  let uploaded: string | undefined;
  if (photo) {
    const saved = await saveMenuPhoto(photo, id);
    if ("error" in saved && saved.error) return { error: saved.error };
    if ("src" in saved) uploaded = saved.src;
  }

  // Fresh read for the existence check: updating an item that was just
  // deleted on another instance must not re-insert it.
  const store = await getFreshStore();
  const existing = store.menu.find((entry) => entry.id === id);
  if (!existing) return { error: "Item not found." };
  const categoryType = normalizeMenuCategoryType(
    store.categoryTypes?.[category] ??
      Object.entries(store.categoryTypes ?? {}).find(([name]) => name.toLowerCase() === category.toLowerCase())?.[1] ??
      "other",
  );

  await upsertMenuItemRecord({
    ...existing,
    name,
    price: Math.round(price),
    category,
    categoryType,
    available,
    styles: stylesFromForm(formData, category, categoryType, existing),
    addons,
    types: typesFromForm(formData),
    image: uploaded ?? (isSafeImage(existing.image) ? existing.image : "/images/logo.png"),
  });
  refresh();
  return { ok: true };
}

export async function setMenuItemAvailable(id: string, available: boolean) {
  await requireMenuEditor();
  await setMenuItemAvailableRecord(id, available);
  refresh();
  return { ok: true };
}

export async function deleteMenuItem(id: string) {
  await requireMenuEditor();
  await deleteMenuItemRecord(id);
  refresh();
  return { ok: true };
}
